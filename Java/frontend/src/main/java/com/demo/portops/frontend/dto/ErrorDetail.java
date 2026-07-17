package com.demo.portops.frontend.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

public record ErrorDetail(
        String code,
        String message,
        @JsonProperty("trace_id") String traceId) {
}
