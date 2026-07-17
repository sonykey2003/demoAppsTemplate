package com.demo.portops.frontend.web;

import com.demo.portops.frontend.client.ContainerClient;
import com.demo.portops.frontend.client.OperationsClient;
import com.demo.portops.frontend.client.VesselClient;
import com.demo.portops.frontend.dto.DashboardData;
import com.demo.portops.frontend.dto.JobDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

import java.util.Collections;
import java.util.List;

@Controller
public class HomeController {

    private static final Logger log = LoggerFactory.getLogger(HomeController.class);

    private final VesselClient vesselClient;
    private final ContainerClient containerClient;
    private final OperationsClient operationsClient;

    public HomeController(VesselClient vesselClient, ContainerClient containerClient,
                          OperationsClient operationsClient) {
        this.vesselClient = vesselClient;
        this.containerClient = containerClient;
        this.operationsClient = operationsClient;
    }

    @GetMapping("/")
    public String dashboard(Model model) {
        log.debug("Loading dashboard");
        int vesselCount = 0;
        int containerCount = 0;
        List<JobDto> recentJobs = Collections.emptyList();

        try {
            var vessels = vesselClient.listVessels();
            vesselCount = vessels != null ? vessels.size() : 0;
        } catch (Exception e) {
            log.warn("Could not fetch vessels for dashboard: {}", e.getMessage());
        }

        try {
            var containers = containerClient.listContainers();
            containerCount = containers != null ? containers.size() : 0;
        } catch (Exception e) {
            log.warn("Could not fetch containers for dashboard: {}", e.getMessage());
        }

        try {
            var allJobs = operationsClient.listJobs();
            if (allJobs != null) {
                recentJobs = allJobs.stream()
                        .sorted((a, b) -> {
                            String ca = a.createdAt() != null ? a.createdAt() : "";
                            String cb = b.createdAt() != null ? b.createdAt() : "";
                            return cb.compareTo(ca);
                        })
                        .limit(10)
                        .toList();
            }
        } catch (Exception e) {
            log.warn("Could not fetch jobs for dashboard: {}", e.getMessage());
        }

        model.addAttribute("dashboard", new DashboardData(vesselCount, containerCount, recentJobs));
        return "index";
    }
}
