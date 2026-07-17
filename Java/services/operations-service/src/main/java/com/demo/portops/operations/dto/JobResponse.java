package com.demo.portops.operations.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.demo.portops.operations.domain.JobStatus;
import com.demo.portops.operations.domain.OperationType;
import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.UUID;

public class JobResponse {

    private UUID id;

    @JsonProperty("vessel_code")
    private String vesselCode;

    @JsonProperty("container_id")
    private String containerId;

    @JsonProperty("operation_type")
    private OperationType operationType;

    @JsonProperty("terminal_id")
    private String terminalId;

    private JobStatus status;

    @JsonProperty("created_at")
    private OffsetDateTime createdAt;

    @JsonProperty("started_at")
    private OffsetDateTime startedAt;

    @JsonProperty("completed_at")
    private OffsetDateTime completedAt;

    @JsonProperty("duration_seconds")
    private BigDecimal durationSeconds;

    public JobResponse() {}

    public JobResponse(UUID id, String vesselCode, String containerId,
                       OperationType operationType, String terminalId,
                       JobStatus status, OffsetDateTime createdAt,
                       OffsetDateTime startedAt, OffsetDateTime completedAt,
                       BigDecimal durationSeconds) {
        this.id = id;
        this.vesselCode = vesselCode;
        this.containerId = containerId;
        this.operationType = operationType;
        this.terminalId = terminalId;
        this.status = status;
        this.createdAt = createdAt;
        this.startedAt = startedAt;
        this.completedAt = completedAt;
        this.durationSeconds = durationSeconds;
    }

    public UUID getId() { return id; }
    public String getVesselCode() { return vesselCode; }
    public String getContainerId() { return containerId; }
    public OperationType getOperationType() { return operationType; }
    public String getTerminalId() { return terminalId; }
    public JobStatus getStatus() { return status; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public OffsetDateTime getStartedAt() { return startedAt; }
    public OffsetDateTime getCompletedAt() { return completedAt; }
    public BigDecimal getDurationSeconds() { return durationSeconds; }
}
