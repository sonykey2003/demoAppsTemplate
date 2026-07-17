package com.demo.portops.operations.web;

import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/operations")
public class OperationsController {

    private final Tracer tracer;

    public OperationsController(Tracer tracer) {
        this.tracer = tracer;
    }

    @GetMapping("/slow")
    public ResponseEntity<Map<String, Object>> slow(
            @RequestParam("delay_ms") int delayMs) {
        if (delayMs < 1 || delayMs > 30000) {
            throw new IllegalArgumentException("delay_ms must be between 1 and 30000");
        }
        Span span = tracer.spanBuilder("ops.simulated_slow")
                .setAttribute("delay_ms", delayMs)
                .startSpan();
        try (var scope = span.makeCurrent()) {
            Thread.sleep(delayMs);
            String traceId = Span.current().getSpanContext().getTraceId();
            return ResponseEntity.ok(Map.of(
                    "message", "Slow operation completed",
                    "delay_ms", delayMs,
                    "trace_id", traceId
            ));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            span.setStatus(StatusCode.ERROR, e.getMessage());
            throw new RuntimeException("Interrupted during slow operation", e);
        } catch (Exception e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw e;
        } finally {
            span.end();
        }
    }

    @GetMapping("/fail")
    public ResponseEntity<Void> fail() {
        Span span = tracer.spanBuilder("ops.simulated_fail").startSpan();
        try (var scope = span.makeCurrent()) {
            RuntimeException ex = new RuntimeException("synthetic failure");
            span.setStatus(StatusCode.ERROR, ex.getMessage());
            span.recordException(ex);
            throw ex;
        } finally {
            span.end();
        }
    }
}
