package com.demo.portops.frontend.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestClient;

@Configuration
public class RestClientConfig {

    private final String vesselServiceUrl;
    private final String containerServiceUrl;
    private final String operationsServiceUrl;

    public RestClientConfig(
            @Value("${app.services.vessel-service-url}") String vesselServiceUrl,
            @Value("${app.services.container-service-url}") String containerServiceUrl,
            @Value("${app.services.operations-service-url}") String operationsServiceUrl) {
        this.vesselServiceUrl = vesselServiceUrl;
        this.containerServiceUrl = containerServiceUrl;
        this.operationsServiceUrl = operationsServiceUrl;
    }

    @Bean("vesselRestClient")
    public RestClient vesselRestClient() {
        return RestClient.builder().baseUrl(vesselServiceUrl).build();
    }

    @Bean("containerRestClient")
    public RestClient containerRestClient() {
        return RestClient.builder().baseUrl(containerServiceUrl).build();
    }

    @Bean("operationsRestClient")
    public RestClient operationsRestClient() {
        return RestClient.builder().baseUrl(operationsServiceUrl).build();
    }
}
