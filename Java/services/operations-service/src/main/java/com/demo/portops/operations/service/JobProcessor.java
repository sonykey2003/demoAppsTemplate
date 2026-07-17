package com.demo.portops.operations.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.demo.portops.operations.domain.Job;
import com.demo.portops.operations.domain.JobRepository;
import com.demo.portops.operations.domain.JobStatus;
import com.demo.portops.operations.domain.OperationType;
import com.demo.portops.operations.dto.ContainerSnapshot;
import com.demo.portops.operations.dto.QueuePayload;
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.context.Context;
import io.opentelemetry.api.metrics.DoubleHistogram;
import io.opentelemetry.api.metrics.Meter;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.TimeUnit;

@Component
public class JobProcessor {

    private static final Logger log = LoggerFactory.getLogger(JobProcessor.class);
    private static final String QUEUE_KEY = "ops:queue:jobs";
    private static final String INFLIGHT_KEY_PREFIX = "ops:inflight:";

    private final JobRepository jobRepository;
    private final StringRedisTemplate redisTemplate;
    private final WebClient containerWebClient;
    private final Tracer tracer;
    private final DoubleHistogram jobDurationHistogram;
    private final DoubleHistogram turnaroundHistogram;
    private final ObjectMapper objectMapper;

    public JobProcessor(JobRepository jobRepository,
                        StringRedisTemplate redisTemplate,
                        @Qualifier("containerWebClient") WebClient containerWebClient,
                        Tracer tracer,
                        Meter meter,
                        DoubleHistogram turnaroundHistogram) {
        this.jobRepository = jobRepository;
        this.redisTemplate = redisTemplate;
        this.containerWebClient = containerWebClient;
        this.tracer = tracer;
        this.jobDurationHistogram = meter.histogramBuilder("ops_job_duration_seconds")
                .setDescription("Job processing duration in seconds")
                .setUnit("s")
                .build();
        this.turnaroundHistogram = turnaroundHistogram;
        this.objectMapper = new ObjectMapper()
                .registerModule(new JavaTimeModule())
                .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
    }

    @Scheduled(fixedDelay = 500)
    public void processNextJob() {
        String raw = redisTemplate.opsForList().rightPop(QUEUE_KEY);
        if (raw == null) return;

        QueuePayload payload;
        try {
            payload = objectMapper.readValue(raw, QueuePayload.class);
        } catch (JsonProcessingException e) {
            log.error("Failed to deserialize queue payload", e);
            return;
        }

        // Restore W3C trace context from traceparent
        String traceparent = payload.getTraceContext();
        Map<String, String> carrier = new HashMap<>();
        if (traceparent != null && !traceparent.isBlank()) {
            carrier.put("traceparent", traceparent);
        }
        Context parentCtx = GlobalOpenTelemetry.getPropagators().getTextMapPropagator()
                .extract(Context.root(), carrier, new io.opentelemetry.context.propagation.TextMapGetter<>() {
                    @Override
                    public Iterable<String> keys(Map<String, String> carrier) {
                        return carrier.keySet();
                    }

                    @Override
                    public String get(Map<String, String> carrier, String key) {
                        return carrier.get(key);
                    }
                });

        try (var ignored = parentCtx.makeCurrent()) {
            processPayload(payload);
        }
    }

    private void processPayload(QueuePayload payload) {
        Optional<Job> optJob = jobRepository.findById(payload.getJobId());
        if (optJob.isEmpty()) {
            log.warn("job_not_found job_id={}", payload.getJobId());
            return;
        }
        Job job = optJob.get();

        MDC.put("terminal_id", job.getTerminalId());
        MDC.put("vessel_code", job.getVesselCode());
        MDC.put("container_id", job.getContainerId());
        MDC.put("operation_type", job.getOperationType().name());
        try {
            // Mark in-progress
            job.setStatus(JobStatus.IN_PROGRESS);
            job.setStartedAt(OffsetDateTime.now());
            jobRepository.save(job);

            // Write inflight key
            redisTemplate.opsForValue().set(
                    INFLIGHT_KEY_PREFIX + job.getId(),
                    payload.getJobId().toString(),
                    300, TimeUnit.SECONDS);

            OperationType opType = job.getOperationType();
            switch (opType) {
                case BERTH_ALLOC -> processBerthAlloc(job);
                case YARD_MOVE -> processYardMove(job);
                case GATE_IN -> processGateAssign(job, "IN_YARD");
                case GATE_OUT -> processGateAssign(job, "GATE_OUT");
            }

            // Complete job
            OffsetDateTime completedAt = OffsetDateTime.now();
            double durationSecs = Duration.between(job.getStartedAt(), completedAt).toMillis() / 1000.0;
            job.setStatus(JobStatus.COMPLETED);
            job.setCompletedAt(completedAt);
            job.setDurationSeconds(BigDecimal.valueOf(durationSecs));
            jobRepository.save(job);

            // Remove inflight
            redisTemplate.delete(INFLIGHT_KEY_PREFIX + job.getId());

            // Record duration metric
            jobDurationHistogram.record(durationSecs, Attributes.builder()
                    .put(AttributeKey.stringKey("operation_type"), opType.name())
                    .put(AttributeKey.stringKey("terminal_id"), job.getTerminalId())
                    .build());

            // Record container turnaround metric (best-effort — job must not fail if lookup fails)
            try {
                ContainerSnapshot container = containerWebClient.get()
                        .uri("/api/containers/{id}", job.getContainerId())
                        .retrieve()
                        .bodyToMono(ContainerSnapshot.class)
                        .block();
                if (container != null) {
                    double turnaroundMinutes = Duration.between(
                            container.createdAt().toInstant(), Instant.now()).toMillis() / 60000.0;
                    turnaroundHistogram.record(turnaroundMinutes, Attributes.builder()
                            .put(AttributeKey.stringKey("iso_type"),
                                    container.isoType() != null ? container.isoType() : "unknown")
                            .put(AttributeKey.stringKey("terminal_id"), job.getTerminalId())
                            .put(AttributeKey.stringKey("operation_type"), opType.name())
                            .build());
                }
            } catch (Exception te) {
                log.warn("turnaround_metric_skipped job_id={} reason={}", job.getId(), te.getMessage());
            }

            log.info("job_completed job_id={} op={} duration_s={}", job.getId(), opType, durationSecs);
        } catch (Exception e) {
            log.error("job_failed job_id={} op={}", job.getId(), job.getOperationType(), e);
            job.setStatus(JobStatus.FAILED);
            job.setCompletedAt(OffsetDateTime.now());
            jobRepository.save(job);
            redisTemplate.delete(INFLIGHT_KEY_PREFIX + job.getId());
        } finally {
            MDC.remove("terminal_id");
            MDC.remove("vessel_code");
            MDC.remove("container_id");
            MDC.remove("operation_type");
        }
    }

    private void processBerthAlloc(Job job) {
        Span span = tracer.spanBuilder("ops.berth_allocate")
                .setAttribute("vessel_code", job.getVesselCode())
                .setAttribute("terminal_id", job.getTerminalId())
                .startSpan();
        try (var scope = span.makeCurrent()) {
            long delay = ThreadLocalRandom.current().nextLong(2000, 8001);
            span.setAttribute("synthetic.delay_ms", delay);
            Thread.sleep(delay);
            patchContainerStatus(job.getContainerId(), "LOADING");
            log.info("berth_allocation_completed vessel={} terminal={}",
                    job.getVesselCode(), job.getTerminalId());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            span.setStatus(StatusCode.ERROR, e.getMessage());
        } catch (Exception e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw e;
        } finally {
            span.end();
        }
    }

    private void processYardMove(Job job) {
        Span yardSpan = tracer.spanBuilder("ops.yard_optimize")
                .setAttribute("container_id", job.getContainerId())
                .setAttribute("terminal_id", job.getTerminalId())
                .startSpan();
        try (var scope = yardSpan.makeCurrent()) {
            long delay = ThreadLocalRandom.current().nextLong(500, 3001);
            yardSpan.setAttribute("synthetic.delay_ms", delay);
            Thread.sleep(delay);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            yardSpan.setStatus(StatusCode.ERROR, e.getMessage());
        } catch (Exception e) {
            yardSpan.setStatus(StatusCode.ERROR, e.getMessage());
            yardSpan.recordException(e);
            throw e;
        } finally {
            yardSpan.end();
        }
    }

    private void processGateAssign(Job job, String targetStatus) {
        Span span = tracer.spanBuilder("ops.container_assign")
                .setAttribute("container_id", job.getContainerId())
                .setAttribute("operation_type", job.getOperationType().name())
                .setAttribute("terminal_id", job.getTerminalId())
                .startSpan();
        try (var scope = span.makeCurrent()) {
            long delay = ThreadLocalRandom.current().nextLong(50, 151);
            Thread.sleep(delay);
            patchContainerStatus(job.getContainerId(), targetStatus);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            span.setStatus(StatusCode.ERROR, e.getMessage());
        } catch (Exception e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw e;
        } finally {
            span.end();
        }
    }

    private void patchContainerStatus(String containerId, String status) {
        containerWebClient.patch()
                .uri("/api/containers/{id}/status", containerId)
                .bodyValue(Map.of("status", status))
                .retrieve()
                .bodyToMono(Void.class)
                .block();
    }
}
