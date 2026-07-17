package com.demo.portops.operations.web;

import com.demo.portops.operations.dto.JobRequest;
import com.demo.portops.operations.dto.JobResponse;
import com.demo.portops.operations.service.JobService;
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
import java.util.UUID;

@RestController
@RequestMapping("/api/jobs")
public class JobController {

    private final JobService jobService;

    public JobController(JobService jobService) {
        this.jobService = jobService;
    }

    @GetMapping
    public ResponseEntity<List<JobResponse>> listAll() {
        return ResponseEntity.ok(jobService.findAll());
    }

    @GetMapping("/{id}")
    public ResponseEntity<JobResponse> getById(@PathVariable UUID id) {
        return jobService.findById(id)
                .map(ResponseEntity::ok)
                .orElseThrow(() -> new JobService.JobNotFoundException(id));
    }

    @PostMapping
    public ResponseEntity<JobResponse> create(@Valid @RequestBody JobRequest request) {
        JobResponse response = jobService.createJob(request);
        return ResponseEntity.status(HttpStatus.ACCEPTED).body(response);
    }
}
