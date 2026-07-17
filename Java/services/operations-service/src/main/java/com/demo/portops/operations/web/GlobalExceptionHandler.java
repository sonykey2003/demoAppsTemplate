package com.demo.portops.operations.web;

import com.demo.portops.operations.dto.ErrorResponse;
import com.demo.portops.operations.service.JobService;
import io.opentelemetry.api.trace.Span;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.stream.Collectors;

@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(JobService.JobNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(JobService.JobNotFoundException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(new ErrorResponse("JOB_NOT_FOUND", ex.getMessage(), traceId()));
    }

    @ExceptionHandler(JobService.DependencyFailedException.class)
    public ResponseEntity<ErrorResponse> handleDependency(JobService.DependencyFailedException ex) {
        return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY)
                .body(new ErrorResponse("JOB_DEPENDENCY_FAILED", ex.getMessage(), traceId()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(MethodArgumentNotValidException ex) {
        String msg = ex.getBindingResult().getFieldErrors().stream()
                .map(e -> e.getField() + ": " + e.getDefaultMessage())
                .collect(Collectors.joining("; "));
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(new ErrorResponse("JOB_VALIDATION_FAILED", msg, traceId()));
    }

    @ExceptionHandler(RuntimeException.class)
    public ResponseEntity<ErrorResponse> handleRuntime(RuntimeException ex) {
        String msg = ex.getMessage();
        if (msg != null && msg.contains("synthetic failure")) {
            log.error("Synthetic failure injected", ex);
            Span.current().recordException(ex);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(new ErrorResponse("OPS_FORCED_FAILURE",
                            "Synthetic failure injected for demo purposes", traceId()));
        }
        log.error("Unexpected runtime error", ex);
        Span.current().recordException(ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(new ErrorResponse("INTERNAL_ERROR", msg, traceId()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneral(Exception ex) {
        log.error("Unexpected error", ex);
        Span.current().recordException(ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(new ErrorResponse("INTERNAL_ERROR", ex.getMessage(), traceId()));
    }

    private String traceId() {
        return Span.current().getSpanContext().getTraceId();
    }
}
