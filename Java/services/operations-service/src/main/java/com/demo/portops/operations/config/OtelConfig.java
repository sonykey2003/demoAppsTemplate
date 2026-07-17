package com.demo.portops.operations.config;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.metrics.DoubleHistogram;
import io.opentelemetry.api.metrics.Meter;
import io.opentelemetry.api.trace.Tracer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OtelConfig {

    @Bean
    public Tracer tracer() {
        return GlobalOpenTelemetry.get().getTracer("com.demo.portops.operations", "0.1.0");
    }

    @Bean
    public Meter meter() {
        return GlobalOpenTelemetry.get().getMeter("com.demo.portops.operations");
    }

    @Bean
    public DoubleHistogram turnaroundHistogram(Meter meter) {
        return meter.histogramBuilder("container_turnaround_minutes")
                .setDescription("Container turnaround time in minutes")
                .setUnit("min")
                .build();
    }
}
