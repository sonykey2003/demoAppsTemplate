package com.demo.portops.frontend.client;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.demo.portops.frontend.dto.ContainerDto;
import com.demo.portops.frontend.dto.ErrorDetail;
import com.demo.portops.frontend.dto.ErrorEnvelope;
import com.demo.portops.frontend.dto.TurnaroundDto;
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
public class ContainerClient {

    private static final Logger log = LoggerFactory.getLogger(ContainerClient.class);

    private final RestClient restClient;
    private final String baseUrl;
    private final Tracer tracer;
    private final ObjectMapper objectMapper;

    public ContainerClient(
            @Qualifier("containerRestClient") RestClient restClient,
            @Value("${app.services.container-service-url}") String baseUrl,
            Tracer tracer,
            ObjectMapper objectMapper) {
        this.restClient = restClient;
        this.baseUrl = baseUrl;
        this.tracer = tracer;
        this.objectMapper = objectMapper;
    }

    public List<ContainerDto> listContainers() {
        Span span = tracer.spanBuilder("frontend.listContainers")
                .setAttribute("downstream_service", "container-service")
                .setAttribute("http.method", "GET")
                .setAttribute("http.url", baseUrl + "/api/containers")
                .startSpan();
        try (Scope ignored = span.makeCurrent()) {
            log.debug("Fetching all containers from container-service");
            return restClient.get()
                    .uri("/api/containers")
                    .retrieve()
                    .body(new ParameterizedTypeReference<>() {});
        } catch (HttpStatusCodeException e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw new BackendException("container-service", e.getStatusCode().value(), parseError(e));
        } catch (ResourceAccessException e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw new ServiceUnavailableException("container-service", e);
        } finally {
            span.end();
        }
    }

    public TurnaroundDto getTurnaround(String containerId) {
        Span span = tracer.spanBuilder("frontend.getContainerTurnaround")
                .setAttribute("downstream_service", "container-service")
                .setAttribute("http.method", "GET")
                .setAttribute("http.url", baseUrl + "/api/containers/" + containerId + "/turnaround")
                .startSpan();
        try (Scope ignored = span.makeCurrent()) {
            log.debug("Fetching turnaround for container {}", containerId);
            return restClient.get()
                    .uri("/api/containers/{id}/turnaround", containerId)
                    .retrieve()
                    .body(TurnaroundDto.class);
        } catch (HttpStatusCodeException e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw new BackendException("container-service", e.getStatusCode().value(), parseError(e));
        } catch (ResourceAccessException e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw new ServiceUnavailableException("container-service", e);
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
