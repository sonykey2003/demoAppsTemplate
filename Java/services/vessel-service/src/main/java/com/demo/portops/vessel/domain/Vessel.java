package com.demo.portops.vessel.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.OffsetDateTime;

@Entity
@Table(name = "vessels")
public class Vessel {

    @Id
    @Column(name = "code", length = 10)
    private String code;

    @Column(name = "name", length = 100, nullable = false)
    private String name;

    @Column(name = "imo", length = 12)
    private String imo;

    @Column(name = "length_m", nullable = false, precision = 6, scale = 1)
    private BigDecimal lengthM;

    @Column(name = "created_at", nullable = false, updatable = false,
            columnDefinition = "TIMESTAMPTZ")
    private OffsetDateTime createdAt;

    public Vessel() {}

    public String getCode() { return code; }
    public void setCode(String code) { this.code = code; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getImo() { return imo; }
    public void setImo(String imo) { this.imo = imo; }

    public BigDecimal getLengthM() { return lengthM; }
    public void setLengthM(BigDecimal lengthM) { this.lengthM = lengthM; }

    public OffsetDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(OffsetDateTime createdAt) { this.createdAt = createdAt; }
}
