package com.demo.portops.vessel.web;

import com.demo.portops.vessel.domain.VesselRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class IdentityController {

    private final VesselRepository vesselRepository;

    public IdentityController(VesselRepository vesselRepository) {
        this.vesselRepository = vesselRepository;
    }

    @GetMapping("/")
    public ResponseEntity<Map<String, String>> identity() {
        return ResponseEntity.ok(Map.of(
                "service", "vessel-service",
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
            vesselRepository.count();
            return ResponseEntity.ok(Map.of("status", "READY"));
        } catch (Exception e) {
            return ResponseEntity.status(503)
                    .body(Map.of("status", "NOT_READY"));
        }
    }
}
