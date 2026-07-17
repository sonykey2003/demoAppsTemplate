package com.demo.portops.frontend.web;

import com.demo.portops.frontend.client.ContainerClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;

@Controller
@RequestMapping("/containers")
public class ContainersController {

    private static final Logger log = LoggerFactory.getLogger(ContainersController.class);

    private final ContainerClient containerClient;

    public ContainersController(ContainerClient containerClient) {
        this.containerClient = containerClient;
    }

    @GetMapping
    public String list(Model model) {
        log.debug("Loading containers list");
        model.addAttribute("containers", containerClient.listContainers());
        return "containers";
    }

    @GetMapping("/{id}")
    public String detail(@PathVariable String id, Model model) {
        log.debug("Loading turnaround detail for container {}", id);
        model.addAttribute("turnaround", containerClient.getTurnaround(id));
        return "containers/detail";
    }
}
