package com.demo.portops.vessel.web;

import com.demo.portops.vessel.dto.VesselRequest;
import com.demo.portops.vessel.dto.VesselResponse;
import com.demo.portops.vessel.service.VesselService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/vessels")
public class VesselController {

    private final VesselService vesselService;

    public VesselController(VesselService vesselService) {
        this.vesselService = vesselService;
    }

    @GetMapping
    public ResponseEntity<List<VesselResponse>> listAll() {
        return ResponseEntity.ok(vesselService.findAll());
    }

    @GetMapping("/{code}")
    public ResponseEntity<VesselResponse> getByCode(@PathVariable String code) {
        return vesselService.findByCode(code)
                .map(ResponseEntity::ok)
                .orElseThrow(() -> new VesselService.VesselNotFoundException(code));
    }

    @PostMapping
    public ResponseEntity<VesselResponse> create(@Valid @RequestBody VesselRequest request) {
        VesselResponse response = vesselService.create(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }
}
