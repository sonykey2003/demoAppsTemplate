package com.demo.portops.frontend.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

public record JobDto(
        String id,
        @JsonProperty("vessel_code") String vesselCode,
        @JsonProperty("container_id") String containerId,
        @JsonProperty("operation_type") String operationType,
        @JsonProperty("terminal_id") String terminalId,
        String status,
        @JsonProperty("created_at") String createdAt,
        @JsonProperty("started_at") String startedAt,
        @JsonProperty("completed_at") String completedAt,
        @JsonProperty("duration_seconds") Double durationSeconds) {
}
