package com.demo.portops.vessel.service;

import com.demo.portops.vessel.domain.Vessel;
import com.demo.portops.vessel.domain.VesselRepository;
import com.demo.portops.vessel.dto.VesselRequest;
import com.demo.portops.vessel.dto.VesselResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

@Service
public class VesselService {

    private static final Logger log = LoggerFactory.getLogger(VesselService.class);

    private final VesselRepository vesselRepository;

    public VesselService(VesselRepository vesselRepository) {
        this.vesselRepository = vesselRepository;
    }

    public List<VesselResponse> findAll() {
        return vesselRepository.findAll()
                .stream()
                .map(this::toResponse)
                .collect(Collectors.toList());
    }

    public Optional<VesselResponse> findByCode(String code) {
        return vesselRepository.findById(code).map(this::toResponse);
    }

    @Transactional
    public VesselResponse create(VesselRequest request) {
        if (vesselRepository.existsById(request.getCode())) {
            throw new DuplicateVesselException(request.getCode());
        }
        Vessel vessel = new Vessel();
        vessel.setCode(request.getCode());
        vessel.setName(request.getName());
        vessel.setImo(request.getImo());
        vessel.setLengthM(request.getLengthM());
        vessel.setCreatedAt(OffsetDateTime.now());
        Vessel saved = vesselRepository.save(vessel);
        log.info("vessel_created code={} name={}", saved.getCode(), saved.getName());
        return toResponse(saved);
    }

    private VesselResponse toResponse(Vessel v) {
        return new VesselResponse(v.getCode(), v.getName(), v.getImo(),
                v.getLengthM(), v.getCreatedAt());
    }

    // ── Custom exceptions ─────────────────────────────────────────────────────

    public static class VesselNotFoundException extends RuntimeException {
        public VesselNotFoundException(String code) {
            super("Vessel with code " + code + " does not exist");
        }
    }

    public static class DuplicateVesselException extends RuntimeException {
        public DuplicateVesselException(String code) {
            super("Vessel with code " + code + " already exists");
        }
    }
}
