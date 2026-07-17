package com.demo.portops.frontend.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

public record TurnaroundDto(
        @JsonProperty("container_id") String containerId,
        String status,
        @JsonProperty("created_at") String createdAt,
        @JsonProperty("last_moved_at") String lastMovedAt,
        @JsonProperty("turnaround_minutes") Double turnaroundMinutes,
        @JsonProperty("is_complete") Boolean isComplete) {
}
