package com.demo.portops.frontend.web;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class HealthController {

    @GetMapping(value = "/healthz", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, String>> healthz() {
        return ResponseEntity.ok(Map.of("status", "UP"));
    }

    @GetMapping(value = "/readyz", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, String>> readyz() {
        return ResponseEntity.ok(Map.of("status", "READY"));
    }
}
