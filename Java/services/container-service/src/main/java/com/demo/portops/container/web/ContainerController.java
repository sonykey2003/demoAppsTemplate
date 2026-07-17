package com.demo.portops.container.web;

import com.demo.portops.container.domain.ContainerStatus;
import com.demo.portops.container.dto.ContainerRequest;
import com.demo.portops.container.dto.ContainerResponse;
import com.demo.portops.container.dto.StatusUpdateRequest;
import com.demo.portops.container.dto.TurnaroundResponse;
import com.demo.portops.container.service.ContainerService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/containers")
public class ContainerController {

    private final ContainerService containerService;

    public ContainerController(ContainerService containerService) {
        this.containerService = containerService;
    }

    @GetMapping
    public ResponseEntity<List<ContainerResponse>> listAll() {
        return ResponseEntity.ok(containerService.findAll());
    }

    @GetMapping("/{id}")
    public ResponseEntity<ContainerResponse> getById(@PathVariable String id) {
        return containerService.findById(id)
                .map(ResponseEntity::ok)
                .orElseThrow(() -> new ContainerService.ContainerNotFoundException(id));
    }

    @PostMapping
    public ResponseEntity<ContainerResponse> create(@Valid @RequestBody ContainerRequest request) {
        ContainerResponse response = containerService.create(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @PatchMapping("/{id}/status")
    public ResponseEntity<ContainerResponse> updateStatus(
            @PathVariable String id,
            @RequestBody StatusUpdateRequest request) {
        ContainerStatus status = request.getStatus();
        if (status == null) {
            throw new IllegalArgumentException("status is required");
        }
        ContainerResponse response = containerService.updateStatus(id, status);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/{id}/turnaround")
    public ResponseEntity<TurnaroundResponse> turnaround(@PathVariable String id) {
        return ResponseEntity.ok(containerService.computeTurnaround(id));
    }
}
