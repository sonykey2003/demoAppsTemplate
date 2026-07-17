package com.demo.portops.vessel.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.math.BigDecimal;
import java.time.OffsetDateTime;

public class VesselResponse {

    private String code;
    private String name;
    private String imo;

    @JsonProperty("length_m")
    private BigDecimal lengthM;

    @JsonProperty("created_at")
    private OffsetDateTime createdAt;

    public VesselResponse() {}

    public VesselResponse(String code, String name, String imo,
                          BigDecimal lengthM, OffsetDateTime createdAt) {
        this.code = code;
        this.name = name;
        this.imo = imo;
        this.lengthM = lengthM;
        this.createdAt = createdAt;
    }

    public String getCode() { return code; }
    public String getName() { return name; }
    public String getImo() { return imo; }
    public BigDecimal getLengthM() { return lengthM; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
}
