package com.demo.portops.container.web;

import com.demo.portops.container.dto.ErrorResponse;
import com.demo.portops.container.service.ContainerService;
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

    @ExceptionHandler(ContainerService.ContainerNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(ContainerService.ContainerNotFoundException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(new ErrorResponse("CONTAINER_NOT_FOUND", ex.getMessage(), traceId()));
    }

    @ExceptionHandler(ContainerService.DuplicateContainerException.class)
    public ResponseEntity<ErrorResponse> handleConflict(ContainerService.DuplicateContainerException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(new ErrorResponse("CONTAINER_ALREADY_EXISTS", ex.getMessage(), traceId()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(MethodArgumentNotValidException ex) {
        String msg = ex.getBindingResult().getFieldErrors().stream()
                .map(e -> e.getField() + ": " + e.getDefaultMessage())
                .collect(Collectors.joining("; "));
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(new ErrorResponse("CONTAINER_VALIDATION_FAILED", msg, traceId()));
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
