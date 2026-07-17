package com.demo.portops.vessel.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;

public class VesselRequest {

    @NotBlank
    @Pattern(regexp = "VSL-\\d{4}", message = "code must match VSL-NNNN")
    private String code;

    @NotBlank
    @Size(min = 1, max = 100)
    private String name;

    @Pattern(regexp = "IMO\\d{7}", message = "imo must match IMO9######")
    private String imo;

    @NotNull
    @DecimalMin(value = "0", inclusive = false, message = "length_m must be > 0")
    @JsonProperty("length_m")
    private BigDecimal lengthM;

    public String getCode() { return code; }
    public void setCode(String code) { this.code = code; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getImo() { return imo; }
    public void setImo(String imo) { this.imo = imo; }

    public BigDecimal getLengthM() { return lengthM; }
    public void setLengthM(BigDecimal lengthM) { this.lengthM = lengthM; }
}
