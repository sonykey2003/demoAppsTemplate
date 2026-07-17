package com.demo.portops.frontend.dto;

import java.util.List;

public record DashboardData(
        int vesselCount,
        int containerCount,
        List<JobDto> recentJobs) {
}
