package com.demo.portops.container.config;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.metrics.Meter;
import io.opentelemetry.api.trace.Tracer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OtelConfig {

    @Bean
    public Tracer tracer() {
        return GlobalOpenTelemetry.get().getTracer("com.demo.portops.container", "0.1.0");
    }

    @Bean
    public Meter meter() {
        return GlobalOpenTelemetry.get().getMeter("com.demo.portops.container");
    }
}
