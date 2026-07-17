package com.demo.portops.operations.web;

import com.demo.portops.operations.domain.JobRepository;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;

import java.util.Map;

@RestController
public class IdentityController {

    private final JobRepository jobRepository;
    private final StringRedisTemplate redisTemplate;
    private final WebClient vesselWebClient;
    private final WebClient containerWebClient;

    public IdentityController(JobRepository jobRepository,
                              StringRedisTemplate redisTemplate,
                              @Qualifier("vesselWebClient") WebClient vesselWebClient,
                              @Qualifier("containerWebClient") WebClient containerWebClient) {
        this.jobRepository = jobRepository;
        this.redisTemplate = redisTemplate;
        this.vesselWebClient = vesselWebClient;
        this.containerWebClient = containerWebClient;
    }

    @GetMapping("/")
    public ResponseEntity<Map<String, String>> identity() {
        return ResponseEntity.ok(Map.of(
                "service", "operations-service",
                "version", "0.1.0",
                "namespace", "port-ops-demo"
        ));
    }

    @GetMapping("/healthz")
    public ResponseEntity<Map<String, String>> healthz() {
        return ResponseEntity.ok(Map.of("status", "UP"));
    }

    @GetMapping("/readyz")
    public ResponseEntity<Map<String, String>> readyz() {
        try {
            jobRepository.count();
            redisTemplate.hasKey("readyz:probe");
            pingDownstream(vesselWebClient);
            pingDownstream(containerWebClient);
            return ResponseEntity.ok(Map.of("status", "READY"));
        } catch (Exception e) {
            return ResponseEntity.status(503).body(Map.of("status", "NOT_READY"));
        }
    }

    private void pingDownstream(WebClient client) {
        client.get().uri("/healthz")
                .retrieve()
                .bodyToMono(String.class)
                .block();
    }
}
