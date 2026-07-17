package com.demo.portops.container.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.demo.portops.container.domain.Container;
import com.demo.portops.container.domain.ContainerRepository;
import com.demo.portops.container.domain.ContainerStatus;
import com.demo.portops.container.dto.ContainerRequest;
import com.demo.portops.container.dto.ContainerResponse;
import com.demo.portops.container.dto.TurnaroundResponse;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

@Service
public class ContainerService {

    private static final Logger log = LoggerFactory.getLogger(ContainerService.class);
    private static final String CACHE_KEY_PREFIX = "container:cache:";
    private static final long CACHE_TTL_SECONDS = 60L;

    private final ContainerRepository containerRepository;
    private final StringRedisTemplate redisTemplate;
    private final Tracer tracer;
    private final ObjectMapper objectMapper;

    public ContainerService(ContainerRepository containerRepository,
                            StringRedisTemplate redisTemplate,
                            Tracer tracer) {
        this.containerRepository = containerRepository;
        this.redisTemplate = redisTemplate;
        this.tracer = tracer;
        this.objectMapper = new ObjectMapper()
                .registerModule(new JavaTimeModule())
                .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
    }

    public List<ContainerResponse> findAll() {
        return containerRepository.findAll().stream()
                .map(this::toResponse)
                .collect(Collectors.toList());
    }

    public Optional<ContainerResponse> findById(String id) {
        String cacheKey = CACHE_KEY_PREFIX + id;
        String cached = redisTemplate.opsForValue().get(cacheKey);
        if (cached != null) {
            log.debug("container_cache_hit id={}", id);
            return Optional.of(deserialize(cached));
        }
        Optional<Container> opt = containerRepository.findById(id);
        opt.ifPresent(c -> {
            try {
                String json = objectMapper.writeValueAsString(toResponse(c));
                redisTemplate.opsForValue().set(cacheKey, json, CACHE_TTL_SECONDS, TimeUnit.SECONDS);
            } catch (JsonProcessingException ex) {
                log.warn("Failed to cache container id={}", id, ex);
            }
        });
        return opt.map(this::toResponse);
    }

    @Transactional
    public ContainerResponse create(ContainerRequest request) {
        if (containerRepository.existsById(request.getId())) {
            throw new DuplicateContainerException(request.getId());
        }
        Container c = new Container();
        c.setId(request.getId());
        c.setIsoType(request.getIsoType());
        c.setWeightKg(request.getWeightKg());
        c.setStatus(request.getStatus() != null ? request.getStatus() : ContainerStatus.INBOUND);
        c.setCreatedAt(OffsetDateTime.now());
        Container saved = containerRepository.save(c);
        log.info("container_created id={} iso_type={} status={}", saved.getId(),
                saved.getIsoType(), saved.getStatus());
        return toResponse(saved);
    }

    @Transactional
    public ContainerResponse updateStatus(String id, ContainerStatus newStatus) {
        Container c = containerRepository.findById(id)
                .orElseThrow(() -> new ContainerNotFoundException(id));
        c.setStatus(newStatus);
        c.setLastMovedAt(OffsetDateTime.now());
        Container saved = containerRepository.save(c);
        redisTemplate.delete(CACHE_KEY_PREFIX + id);
        log.info("container_status_updated id={} status={}", id, newStatus);
        return toResponse(saved);
    }

    public TurnaroundResponse computeTurnaround(String id) {
        Container c = containerRepository.findById(id)
                .orElseThrow(() -> new ContainerNotFoundException(id));

        Span span = tracer.spanBuilder("ops.container_turnaround")
                .setAttribute("container_id", id)
                .setAttribute("iso_type", c.getIsoType())
                .startSpan();
        try (var scope = span.makeCurrent()) {
            OffsetDateTime end = c.getLastMovedAt() != null ? c.getLastMovedAt() : OffsetDateTime.now();
            double minutes = Duration.between(c.getCreatedAt(), end).toSeconds() / 60.0;
            boolean complete = c.getLastMovedAt() != null;

            return new TurnaroundResponse(id, c.getStatus(), c.getCreatedAt(),
                    c.getLastMovedAt(), minutes, complete);
        } catch (Exception e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw e;
        } finally {
            span.end();
        }
    }

    private ContainerResponse toResponse(Container c) {
        return new ContainerResponse(c.getId(), c.getIsoType(), c.getWeightKg(),
                c.getStatus(), c.getCreatedAt(), c.getLastMovedAt());
    }

    private ContainerResponse deserialize(String json) {
        try {
            return objectMapper.readValue(json, ContainerResponse.class);
        } catch (JsonProcessingException e) {
            throw new RuntimeException("Failed to deserialize container from cache", e);
        }
    }

    // ── Custom exceptions ────────────────────────────────────────────────────

    public static class ContainerNotFoundException extends RuntimeException {
        public ContainerNotFoundException(String id) {
            super("Container with id " + id + " does not exist");
        }
    }

    public static class DuplicateContainerException extends RuntimeException {
        public DuplicateContainerException(String id) {
            super("Container with id " + id + " already exists");
        }
    }
}
