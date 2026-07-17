package com.demo.portops.operations.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.client.WebClient;

@Configuration
public class WebClientConfig {

    @Value("${app.services.vessel-service-url}")
    private String vesselServiceUrl;

    @Value("${app.services.container-service-url}")
    private String containerServiceUrl;

    @Bean("vesselWebClient")
    public WebClient vesselWebClient(WebClient.Builder builder) {
        return builder.baseUrl(vesselServiceUrl).build();
    }

    @Bean("containerWebClient")
    public WebClient containerWebClient(WebClient.Builder builder) {
        return builder.baseUrl(containerServiceUrl).build();
    }
}
