package com.demo.portops.container.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.demo.portops.container.domain.ContainerStatus;
import java.time.OffsetDateTime;

public class ContainerResponse {

    private String id;

    @JsonProperty("iso_type")
    private String isoType;

    @JsonProperty("weight_kg")
    private Integer weightKg;

    private ContainerStatus status;

    @JsonProperty("created_at")
    private OffsetDateTime createdAt;

    @JsonProperty("last_moved_at")
    private OffsetDateTime lastMovedAt;

    public ContainerResponse() {}

    public ContainerResponse(String id, String isoType, Integer weightKg,
                             ContainerStatus status, OffsetDateTime createdAt,
                             OffsetDateTime lastMovedAt) {
        this.id = id;
        this.isoType = isoType;
        this.weightKg = weightKg;
        this.status = status;
        this.createdAt = createdAt;
        this.lastMovedAt = lastMovedAt;
    }

    public String getId() { return id; }
    public String getIsoType() { return isoType; }
    public Integer getWeightKg() { return weightKg; }
    public ContainerStatus getStatus() { return status; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public OffsetDateTime getLastMovedAt() { return lastMovedAt; }
}
