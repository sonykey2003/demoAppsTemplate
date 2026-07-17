package com.demo.portops.operations.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.time.OffsetDateTime;

public record ContainerSnapshot(
    String id,
    @JsonProperty("iso_type") String isoType,
    @JsonProperty("created_at") OffsetDateTime createdAt,
    @JsonProperty("last_moved_at") OffsetDateTime lastMovedAt
) {}
