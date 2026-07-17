package com.demo.portops.container.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.demo.portops.container.domain.ContainerStatus;
import java.time.OffsetDateTime;

public class TurnaroundResponse {

    @JsonProperty("container_id")
    private String containerId;

    private ContainerStatus status;

    @JsonProperty("created_at")
    private OffsetDateTime createdAt;

    @JsonProperty("last_moved_at")
    private OffsetDateTime lastMovedAt;

    @JsonProperty("turnaround_minutes")
    private double turnaroundMinutes;

    @JsonProperty("is_complete")
    private boolean isComplete;

    public TurnaroundResponse() {}

    public TurnaroundResponse(String containerId, ContainerStatus status,
                              OffsetDateTime createdAt, OffsetDateTime lastMovedAt,
                              double turnaroundMinutes, boolean isComplete) {
        this.containerId = containerId;
        this.status = status;
        this.createdAt = createdAt;
        this.lastMovedAt = lastMovedAt;
        this.turnaroundMinutes = turnaroundMinutes;
        this.isComplete = isComplete;
    }

    public String getContainerId() { return containerId; }
    public ContainerStatus getStatus() { return status; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public OffsetDateTime getLastMovedAt() { return lastMovedAt; }
    public double getTurnaroundMinutes() { return turnaroundMinutes; }
    public boolean getIsComplete() { return isComplete; }
}
