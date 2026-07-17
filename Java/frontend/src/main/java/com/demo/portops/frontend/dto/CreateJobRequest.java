package com.demo.portops.frontend.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

public record CreateJobRequest(
        @JsonProperty("vessel_code") String vesselCode,
        @JsonProperty("container_id") String containerId,
        @JsonProperty("operation_type") String operationType,
        @JsonProperty("terminal_id") String terminalId) {
}
