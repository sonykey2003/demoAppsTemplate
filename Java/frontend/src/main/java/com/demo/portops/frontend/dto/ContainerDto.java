package com.demo.portops.frontend.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

public record ContainerDto(
        String id,
        @JsonProperty("iso_type") String isoType,
        @JsonProperty("weight_kg") Integer weightKg,
        String status,
        @JsonProperty("created_at") String createdAt,
        @JsonProperty("last_moved_at") String lastMovedAt) {
}
