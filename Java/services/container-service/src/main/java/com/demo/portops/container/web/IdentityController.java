package com.demo.portops.container.web;

import com.demo.portops.container.domain.ContainerRepository;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class IdentityController {

    private final ContainerRepository containerRepository;
    private final StringRedisTemplate redisTemplate;

    public IdentityController(ContainerRepository containerRepository,
                              StringRedisTemplate redisTemplate) {
        this.containerRepository = containerRepository;
        this.redisTemplate = redisTemplate;
    }

    @GetMapping("/")
    public ResponseEntity<Map<String, String>> identity() {
        return ResponseEntity.ok(Map.of(
                "service", "container-service",
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
            containerRepository.count();
            redisTemplate.hasKey("readyz:probe");
            return ResponseEntity.ok(Map.of("status", "READY"));
        } catch (Exception e) {
            return ResponseEntity.status(503).body(Map.of("status", "NOT_READY"));
        }
    }
}
