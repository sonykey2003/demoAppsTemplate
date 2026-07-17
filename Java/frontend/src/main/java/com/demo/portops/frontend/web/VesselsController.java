package com.demo.portops.frontend.web;

import com.demo.portops.frontend.client.VesselClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;

@Controller
@RequestMapping("/vessels")
public class VesselsController {

    private static final Logger log = LoggerFactory.getLogger(VesselsController.class);

    private final VesselClient vesselClient;

    public VesselsController(VesselClient vesselClient) {
        this.vesselClient = vesselClient;
    }

    @GetMapping
    public String list(Model model) {
        log.debug("Loading vessels list");
        model.addAttribute("vessels", vesselClient.listVessels());
        return "vessels";
    }
}
