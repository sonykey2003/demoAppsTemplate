package com.demo.portops.container.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.demo.portops.container.domain.ContainerStatus;

public class StatusUpdateRequest {

    @JsonProperty("status")
    private ContainerStatus status;

    public ContainerStatus getStatus() { return status; }
    public void setStatus(ContainerStatus status) { this.status = status; }
}
