package com.demo.portops.frontend.config;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Tracer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OtelConfig {

    @Bean
    public Tracer tracer() {
        return GlobalOpenTelemetry.get().getTracer("com.demo.portops.frontend", "0.1.0");
    }
}
