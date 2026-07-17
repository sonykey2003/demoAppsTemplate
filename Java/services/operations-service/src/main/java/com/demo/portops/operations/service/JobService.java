package com.demo.portops.operations.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.demo.portops.operations.domain.Job;
import com.demo.portops.operations.domain.JobRepository;
import com.demo.portops.operations.domain.JobStatus;
import com.demo.portops.operations.dto.JobRequest;
import com.demo.portops.operations.dto.JobResponse;
import com.demo.portops.operations.dto.QueuePayload;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.context.Context;
import io.opentelemetry.api.metrics.LongCounter;
import io.opentelemetry.api.metrics.Meter;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.api.GlobalOpenTelemetry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;

import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class JobService {

    private static final Logger log = LoggerFactory.getLogger(JobService.class);
    private static final String QUEUE_KEY = "ops:queue:jobs";

    private final JobRepository jobRepository;
    private final StringRedisTemplate redisTemplate;
    private final WebClient vesselWebClient;
    private final WebClient containerWebClient;
    private final Tracer tracer;
    private final LongCounter jobCreatedCounter;
    private final ObjectMapper objectMapper;

    public JobService(JobRepository jobRepository,
                      StringRedisTemplate redisTemplate,
                      @Qualifier("vesselWebClient") WebClient vesselWebClient,
                      @Qualifier("containerWebClient") WebClient containerWebClient,
                      Tracer tracer,
                      Meter meter) {
        this.jobRepository = jobRepository;
        this.redisTemplate = redisTemplate;
        this.vesselWebClient = vesselWebClient;
        this.containerWebClient = containerWebClient;
        this.tracer = tracer;
        this.jobCreatedCounter = meter.counterBuilder("ops_job_created_total")
                .setDescription("Total number of jobs created")
                .setUnit("{jobs}")
                .build();
        this.objectMapper = new ObjectMapper()
                .registerModule(new JavaTimeModule())
                .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
    }

    public List<JobResponse> findAll() {
        return jobRepository.findAll().stream()
                .map(this::toResponse)
                .collect(Collectors.toList());
    }

    public Optional<JobResponse> findById(UUID id) {
        return jobRepository.findById(id).map(this::toResponse);
    }

    @Transactional
    public JobResponse createJob(JobRequest request) {
        Span jobSpan = tracer.spanBuilder("ops.job_create")
                .setAttribute("terminal_id", request.getTerminalId())
                .setAttribute("vessel_code", request.getVesselCode())
                .setAttribute("container_id", request.getContainerId())
                .setAttribute("operation_type", request.getOperationType().name())
                .startSpan();
        try (var scope = jobSpan.makeCurrent()) {
            // Validate vessel
            validateVessel(request.getVesselCode(), request.getOperationType().name());
            // Validate container
            validateContainer(request.getContainerId(), request.getOperationType().name());

            // Persist job
            Job job = new Job();
            job.setVesselCode(request.getVesselCode());
            job.setContainerId(request.getContainerId());
            job.setOperationType(request.getOperationType());
            job.setTerminalId(request.getTerminalId());
            job.setStatus(JobStatus.QUEUED);
            job.setCreatedAt(OffsetDateTime.now());
            Job saved = jobRepository.save(job);

            // Capture traceparent
            String traceparent = captureTraceparent();

            // Push to Redis queue
            QueuePayload payload = new QueuePayload(
                    saved.getId(), saved.getVesselCode(), saved.getContainerId(),
                    saved.getOperationType(), saved.getTerminalId(),
                    saved.getCreatedAt(), traceparent);
            try {
                String json = objectMapper.writeValueAsString(payload);
                redisTemplate.opsForList().leftPush(QUEUE_KEY, json);
            } catch (JsonProcessingException e) {
                log.error("Failed to serialize queue payload for job_id={}", saved.getId(), e);
            }

            // Record metric
            jobCreatedCounter.add(1, Attributes.builder()
                    .put(AttributeKey.stringKey("operation_type"), request.getOperationType().name())
                    .put(AttributeKey.stringKey("terminal_id"), request.getTerminalId())
                    .put(AttributeKey.stringKey("status"), "QUEUED")
                    .build());

            log.info("job_created job_id={} vessel={} container={} op={} terminal={}",
                    saved.getId(), saved.getVesselCode(), saved.getContainerId(),
                    saved.getOperationType(), saved.getTerminalId());

            return toResponse(saved);
        } catch (Exception e) {
            jobSpan.setStatus(StatusCode.ERROR, e.getMessage());
            jobSpan.recordException(e);
            throw e;
        } finally {
            jobSpan.end();
        }
    }

    private void validateVessel(String vesselCode, String opType) {
        Span span = tracer.spanBuilder("ops.vessel_validate")
                .setAttribute("vessel_code", vesselCode)
                .setAttribute("operation_type", opType)
                .startSpan();
        try (var scope = span.makeCurrent()) {
            vesselWebClient.get()
                    .uri("/api/vessels/{code}", vesselCode)
                    .retrieve()
                    .bodyToMono(String.class)
                    .block();
        } catch (WebClientResponseException.NotFound e) {
            span.setStatus(StatusCode.ERROR, "Vessel not found: " + vesselCode);
            throw new DependencyFailedException("Vessel not found: " + vesselCode);
        } catch (Exception e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw new DependencyFailedException("Vessel lookup failed: " + e.getMessage());
        } finally {
            span.end();
        }
    }

    private void validateContainer(String containerId, String opType) {
        Span span = tracer.spanBuilder("ops.container_fetch")
                .setAttribute("container_id", containerId)
                .setAttribute("operation_type", opType)
                .startSpan();
        try (var scope = span.makeCurrent()) {
            containerWebClient.get()
                    .uri("/api/containers/{id}", containerId)
                    .retrieve()
                    .bodyToMono(String.class)
                    .block();
        } catch (WebClientResponseException.NotFound e) {
            span.setStatus(StatusCode.ERROR, "Container not found: " + containerId);
            throw new DependencyFailedException("Container not found: " + containerId);
        } catch (Exception e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw new DependencyFailedException("Container lookup failed: " + e.getMessage());
        } finally {
            span.end();
        }
    }

    private String captureTraceparent() {
        Map<String, String> carrier = new HashMap<>();
        GlobalOpenTelemetry.getPropagators().getTextMapPropagator()
                .inject(Context.current(), carrier, (c, key, value) -> c.put(key, value));
        return carrier.getOrDefault("traceparent", "");
    }

    public JobResponse toResponse(Job job) {
        return new JobResponse(job.getId(), job.getVesselCode(), job.getContainerId(),
                job.getOperationType(), job.getTerminalId(), job.getStatus(),
                job.getCreatedAt(), job.getStartedAt(), job.getCompletedAt(),
                job.getDurationSeconds());
    }

    // ── Custom exceptions ────────────────────────────────────────────────────

    public static class JobNotFoundException extends RuntimeException {
        public JobNotFoundException(UUID id) {
            super("Job with id " + id + " does not exist");
        }
    }

    public static class DependencyFailedException extends RuntimeException {
        public DependencyFailedException(String message) {
            super(message);
        }
    }
}
