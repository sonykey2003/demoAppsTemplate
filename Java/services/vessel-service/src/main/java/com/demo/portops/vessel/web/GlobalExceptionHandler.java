package com.demo.portops.vessel.web;

import com.demo.portops.vessel.dto.ErrorResponse;
import com.demo.portops.vessel.service.VesselService;
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

    @ExceptionHandler(VesselService.VesselNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(VesselService.VesselNotFoundException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(new ErrorResponse("VESSEL_NOT_FOUND", ex.getMessage(), traceId()));
    }

    @ExceptionHandler(VesselService.DuplicateVesselException.class)
    public ResponseEntity<ErrorResponse> handleConflict(VesselService.DuplicateVesselException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(new ErrorResponse("VESSEL_ALREADY_EXISTS", ex.getMessage(), traceId()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(MethodArgumentNotValidException ex) {
        String msg = ex.getBindingResult().getFieldErrors().stream()
                .map(e -> e.getField() + ": " + e.getDefaultMessage())
                .collect(Collectors.joining("; "));
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(new ErrorResponse("VESSEL_VALIDATION_FAILED", msg, traceId()));
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
