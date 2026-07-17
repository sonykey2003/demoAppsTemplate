package com.demo.portops.vessel.domain;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface VesselRepository extends JpaRepository<Vessel, String> {
}
