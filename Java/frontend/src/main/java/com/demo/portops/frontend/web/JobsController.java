package com.demo.portops.frontend.web;

import com.demo.portops.frontend.client.ContainerClient;
import com.demo.portops.frontend.client.OperationsClient;
import com.demo.portops.frontend.client.VesselClient;
import com.demo.portops.frontend.dto.CreateJobRequest;
import com.demo.portops.frontend.dto.JobDto;
import com.demo.portops.frontend.exception.BackendException;
import com.demo.portops.frontend.exception.ServiceUnavailableException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import java.util.List;

@Controller
@RequestMapping("/jobs")
public class JobsController {

    private static final Logger log = LoggerFactory.getLogger(JobsController.class);

    private static final List<String> OPERATION_TYPES =
            List.of("YARD_MOVE", "GATE_IN", "GATE_OUT", "BERTH_ALLOC");

    private final OperationsClient operationsClient;
    private final VesselClient vesselClient;
    private final ContainerClient containerClient;

    public JobsController(OperationsClient operationsClient, VesselClient vesselClient,
                          ContainerClient containerClient) {
        this.operationsClient = operationsClient;
        this.vesselClient = vesselClient;
        this.containerClient = containerClient;
    }

    @GetMapping("/new")
    public String newJobForm(Model model) {
        log.debug("Loading new job form");
        model.addAttribute("vessels", vesselClient.listVessels());
        model.addAttribute("containers", containerClient.listContainers());
        model.addAttribute("operationTypes", OPERATION_TYPES);
        return "jobs/new";
    }

    @PostMapping("/new")
    public String submitJob(
            @RequestParam("vesselCode") String vesselCode,
            @RequestParam("containerId") String containerId,
            @RequestParam("operationType") String operationType,
            @RequestParam("terminalId") String terminalId,
            Model model,
            RedirectAttributes redirectAttrs) {
        log.debug("Submitting job: vessel={} container={} op={} terminal={}",
                vesselCode, containerId, operationType, terminalId);
        try {
            JobDto job = operationsClient.createJob(
                    new CreateJobRequest(vesselCode, containerId, operationType, terminalId));
            return "redirect:/jobs/" + job.id();
        } catch (BackendException e) {
            log.warn("Job creation failed [{}]: {}", e.getStatusCode(), e.getMessage());
            model.addAttribute("errorMessage",
                    e.getErrorDetail() != null ? e.getErrorDetail().message() : e.getMessage());
            model.addAttribute("vessels", vesselClient.listVessels());
            model.addAttribute("containers", containerClient.listContainers());
            model.addAttribute("operationTypes", OPERATION_TYPES);
            model.addAttribute("selectedVessel", vesselCode);
            model.addAttribute("selectedContainer", containerId);
            model.addAttribute("selectedOpType", operationType);
            model.addAttribute("terminalId", terminalId);
            return "jobs/new";
        } catch (ServiceUnavailableException e) {
            log.error("Operations service unavailable: {}", e.getMessage());
            model.addAttribute("errorMessage", "Operations service is currently unavailable.");
            model.addAttribute("vessels", vesselClient.listVessels());
            model.addAttribute("containers", containerClient.listContainers());
            model.addAttribute("operationTypes", OPERATION_TYPES);
            return "jobs/new";
        }
    }

    @GetMapping("/{id}")
    public String jobDetail(@PathVariable String id, Model model) {
        log.debug("Loading job detail for id {}", id);
        model.addAttribute("job", operationsClient.getJob(id));
        return "jobs/detail";
    }
}
