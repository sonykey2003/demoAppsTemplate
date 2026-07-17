package com.demo.portops.container.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.demo.portops.container.domain.ContainerStatus;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public class ContainerRequest {

    @NotBlank
    @Pattern(regexp = "CONT-\\d{7}", message = "id must match CONT-NNNNNNN")
    private String id;

    @NotBlank
    @Size(min = 4, max = 4, message = "iso_type must be exactly 4 characters")
    @JsonProperty("iso_type")
    private String isoType;

    @NotNull
    @Min(value = 1, message = "weight_kg must be > 0")
    @Max(value = 30480, message = "weight_kg must be <= 30480")
    @JsonProperty("weight_kg")
    private Integer weightKg;

    @NotNull
    private ContainerStatus status;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getIsoType() { return isoType; }
    public void setIsoType(String isoType) { this.isoType = isoType; }

    public Integer getWeightKg() { return weightKg; }
    public void setWeightKg(Integer weightKg) { this.weightKg = weightKg; }

    public ContainerStatus getStatus() { return status; }
    public void setStatus(ContainerStatus status) { this.status = status; }
}
