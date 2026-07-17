package com.demo.portops.frontend.client;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.demo.portops.frontend.dto.ErrorDetail;
import com.demo.portops.frontend.dto.ErrorEnvelope;
import com.demo.portops.frontend.dto.VesselDto;
import com.demo.portops.frontend.exception.BackendException;
import com.demo.portops.frontend.exception.ServiceUnavailableException;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;

import java.nio.charset.StandardCharsets;
import java.util.List;

@Component
public class VesselClient {

    private static final Logger log = LoggerFactory.getLogger(VesselClient.class);

    private final RestClient restClient;
    private final String baseUrl;
    private final Tracer tracer;
    private final ObjectMapper objectMapper;

    public VesselClient(
            @Qualifier("vesselRestClient") RestClient restClient,
            @Value("${app.services.vessel-service-url}") String baseUrl,
            Tracer tracer,
            ObjectMapper objectMapper) {
        this.restClient = restClient;
        this.baseUrl = baseUrl;
        this.tracer = tracer;
        this.objectMapper = objectMapper;
    }

    public List<VesselDto> listVessels() {
        Span span = tracer.spanBuilder("frontend.listVessels")
                .setAttribute("downstream_service", "vessel-service")
                .setAttribute("http.method", "GET")
                .setAttribute("http.url", baseUrl + "/api/vessels")
                .startSpan();
        try (Scope ignored = span.makeCurrent()) {
            log.debug("Fetching all vessels from vessel-service");
            return restClient.get()
                    .uri("/api/vessels")
                    .retrieve()
                    .body(new ParameterizedTypeReference<>() {});
        } catch (HttpStatusCodeException e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw new BackendException("vessel-service", e.getStatusCode().value(), parseError(e));
        } catch (ResourceAccessException e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw new ServiceUnavailableException("vessel-service", e);
        } finally {
            span.end();
        }
    }

    private ErrorDetail parseError(HttpStatusCodeException e) {
        try {
            String body = new String(e.getResponseBodyAsByteArray(), StandardCharsets.UTF_8);
            ErrorEnvelope env = objectMapper.readValue(body, ErrorEnvelope.class);
            return env != null ? env.error() : null;
        } catch (Exception ex) {
            return new ErrorDetail("BACKEND_ERROR", e.getMessage(), "");
        }
    }
}
