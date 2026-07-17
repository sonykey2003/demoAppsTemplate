package com.demo.portops.container.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.OffsetDateTime;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "containers")
public class Container {

    @Id
    @Column(name = "id", length = 12)
    private String id;

    @Column(name = "iso_type", length = 4, nullable = false)
    private String isoType;

    @Column(name = "weight_kg", nullable = false)
    private Integer weightKg;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(name = "status", nullable = false,
            columnDefinition = "container_status")
    private ContainerStatus status;

    @Column(name = "created_at", nullable = false, updatable = false,
            columnDefinition = "TIMESTAMPTZ")
    private OffsetDateTime createdAt;

    @Column(name = "last_moved_at", columnDefinition = "TIMESTAMPTZ")
    private OffsetDateTime lastMovedAt;

    public Container() {}

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getIsoType() { return isoType; }
    public void setIsoType(String isoType) { this.isoType = isoType; }

    public Integer getWeightKg() { return weightKg; }
    public void setWeightKg(Integer weightKg) { this.weightKg = weightKg; }

    public ContainerStatus getStatus() { return status; }
    public void setStatus(ContainerStatus status) { this.status = status; }

    public OffsetDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(OffsetDateTime createdAt) { this.createdAt = createdAt; }

    public OffsetDateTime getLastMovedAt() { return lastMovedAt; }
    public void setLastMovedAt(OffsetDateTime lastMovedAt) { this.lastMovedAt = lastMovedAt; }
}
