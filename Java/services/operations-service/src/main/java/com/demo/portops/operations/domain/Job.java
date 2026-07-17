package com.demo.portops.operations.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "jobs")
public class Job {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "id", updatable = false, nullable = false, columnDefinition = "UUID")
    private UUID id;

    @Column(name = "vessel_code", length = 10, nullable = false)
    private String vesselCode;

    @Column(name = "container_id", length = 12, nullable = false)
    private String containerId;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(name = "operation_type", nullable = false,
            columnDefinition = "operation_type")
    private OperationType operationType;

    @Column(name = "terminal_id", length = 20, nullable = false)
    private String terminalId;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(name = "status", nullable = false,
            columnDefinition = "job_status")
    private JobStatus status;

    @Column(name = "created_at", nullable = false, updatable = false,
            columnDefinition = "TIMESTAMPTZ")
    private OffsetDateTime createdAt;

    @Column(name = "started_at", columnDefinition = "TIMESTAMPTZ")
    private OffsetDateTime startedAt;

    @Column(name = "completed_at", columnDefinition = "TIMESTAMPTZ")
    private OffsetDateTime completedAt;

    @Column(name = "duration_seconds", precision = 10, scale = 3)
    private BigDecimal durationSeconds;

    public Job() {}

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }

    public String getVesselCode() { return vesselCode; }
    public void setVesselCode(String vesselCode) { this.vesselCode = vesselCode; }

    public String getContainerId() { return containerId; }
    public void setContainerId(String containerId) { this.containerId = containerId; }

    public OperationType getOperationType() { return operationType; }
    public void setOperationType(OperationType operationType) { this.operationType = operationType; }

    public String getTerminalId() { return terminalId; }
    public void setTerminalId(String terminalId) { this.terminalId = terminalId; }

    public JobStatus getStatus() { return status; }
    public void setStatus(JobStatus status) { this.status = status; }

    public OffsetDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(OffsetDateTime createdAt) { this.createdAt = createdAt; }

    public OffsetDateTime getStartedAt() { return startedAt; }
    public void setStartedAt(OffsetDateTime startedAt) { this.startedAt = startedAt; }

    public OffsetDateTime getCompletedAt() { return completedAt; }
    public void setCompletedAt(OffsetDateTime completedAt) { this.completedAt = completedAt; }

    public BigDecimal getDurationSeconds() { return durationSeconds; }
    public void setDurationSeconds(BigDecimal durationSeconds) { this.durationSeconds = durationSeconds; }
}
