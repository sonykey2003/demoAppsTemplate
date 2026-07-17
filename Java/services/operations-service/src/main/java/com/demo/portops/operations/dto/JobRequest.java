package com.demo.portops.operations.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.demo.portops.operations.domain.OperationType;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public class JobRequest {

    @NotBlank
    @Pattern(regexp = "VSL-\\d{4}", message = "vessel_code must match VSL-NNNN")
    @JsonProperty("vessel_code")
    private String vesselCode;

    @NotBlank
    @Pattern(regexp = "CONT-\\d{7}", message = "container_id must match CONT-NNNNNNN")
    @JsonProperty("container_id")
    private String containerId;

    @NotNull
    @JsonProperty("operation_type")
    private OperationType operationType;

    @NotBlank
    @Size(min = 1, max = 20)
    @JsonProperty("terminal_id")
    private String terminalId;

    public String getVesselCode() { return vesselCode; }
    public void setVesselCode(String vesselCode) { this.vesselCode = vesselCode; }

    public String getContainerId() { return containerId; }
    public void setContainerId(String containerId) { this.containerId = containerId; }

    public OperationType getOperationType() { return operationType; }
    public void setOperationType(OperationType operationType) { this.operationType = operationType; }

    public String getTerminalId() { return terminalId; }
    public void setTerminalId(String terminalId) { this.terminalId = terminalId; }
}
