package com.demo.portops.frontend.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

public record VesselDto(
        String code,
        String name,
        String imo,
        @JsonProperty("length_m") Double lengthM,
        @JsonProperty("created_at") String createdAt) {
}
