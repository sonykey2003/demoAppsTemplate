package com.demo.portops.operations.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.demo.portops.operations.domain.OperationType;
import java.time.OffsetDateTime;
import java.util.UUID;

public class QueuePayload {

    @JsonProperty("job_id")
    private UUID jobId;

    @JsonProperty("vessel_code")
    private String vesselCode;

    @JsonProperty("container_id")
    private String containerId;

    @JsonProperty("operation_type")
    private OperationType operationType;

    @JsonProperty("terminal_id")
    private String terminalId;

    @JsonProperty("enqueued_at")
    private OffsetDateTime enqueuedAt;

    @JsonProperty("trace_context")
    private String traceContext;

    public QueuePayload() {}

    public QueuePayload(UUID jobId, String vesselCode, String containerId,
                        OperationType operationType, String terminalId,
                        OffsetDateTime enqueuedAt, String traceContext) {
        this.jobId = jobId;
        this.vesselCode = vesselCode;
        this.containerId = containerId;
        this.operationType = operationType;
        this.terminalId = terminalId;
        this.enqueuedAt = enqueuedAt;
        this.traceContext = traceContext;
    }

    public UUID getJobId() { return jobId; }
    public void setJobId(UUID jobId) { this.jobId = jobId; }

    public String getVesselCode() { return vesselCode; }
    public void setVesselCode(String vesselCode) { this.vesselCode = vesselCode; }

    public String getContainerId() { return containerId; }
    public void setContainerId(String containerId) { this.containerId = containerId; }

    public OperationType getOperationType() { return operationType; }
    public void setOperationType(OperationType operationType) { this.operationType = operationType; }

    public String getTerminalId() { return terminalId; }
    public void setTerminalId(String terminalId) { this.terminalId = terminalId; }

    public OffsetDateTime getEnqueuedAt() { return enqueuedAt; }
    public void setEnqueuedAt(OffsetDateTime enqueuedAt) { this.enqueuedAt = enqueuedAt; }

    public String getTraceContext() { return traceContext; }
    public void setTraceContext(String traceContext) { this.traceContext = traceContext; }
}
