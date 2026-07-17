package com.demo.portops.frontend.client;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.demo.portops.frontend.dto.CreateJobRequest;
import com.demo.portops.frontend.dto.ErrorDetail;
import com.demo.portops.frontend.dto.ErrorEnvelope;
import com.demo.portops.frontend.dto.JobDto;
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
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;

import java.nio.charset.StandardCharsets;
import java.util.List;

@Component
public class OperationsClient {

    private static final Logger log = LoggerFactory.getLogger(OperationsClient.class);

    private final RestClient restClient;
    private final String baseUrl;
    private final Tracer tracer;
    private final ObjectMapper objectMapper;

    public OperationsClient(
            @Qualifier("operationsRestClient") RestClient restClient,
            @Value("${app.services.operations-service-url}") String baseUrl,
            Tracer tracer,
            ObjectMapper objectMapper) {
        this.restClient = restClient;
        this.baseUrl = baseUrl;
        this.tracer = tracer;
        this.objectMapper = objectMapper;
    }

    public List<JobDto> listJobs() {
        Span span = tracer.spanBuilder("frontend.listJobs")
                .setAttribute("downstream_service", "operations-service")
                .setAttribute("http.method", "GET")
                .setAttribute("http.url", baseUrl + "/api/jobs")
                .startSpan();
        try (Scope ignored = span.makeCurrent()) {
            log.debug("Fetching all jobs from operations-service");
            return restClient.get()
                    .uri("/api/jobs")
                    .retrieve()
                    .body(new ParameterizedTypeReference<>() {});
        } catch (HttpStatusCodeException e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw new BackendException("operations-service", e.getStatusCode().value(), parseError(e));
        } catch (ResourceAccessException e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw new ServiceUnavailableException("operations-service", e);
        } finally {
            span.end();
        }
    }

    public JobDto getJob(String id) {
        Span span = tracer.spanBuilder("frontend.getJob")
                .setAttribute("downstream_service", "operations-service")
                .setAttribute("http.method", "GET")
                .setAttribute("http.url", baseUrl + "/api/jobs/" + id)
                .startSpan();
        try (Scope ignored = span.makeCurrent()) {
            log.debug("Fetching job {} from operations-service", id);
            return restClient.get()
                    .uri("/api/jobs/{id}", id)
                    .retrieve()
                    .body(JobDto.class);
        } catch (HttpStatusCodeException e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw new BackendException("operations-service", e.getStatusCode().value(), parseError(e));
        } catch (ResourceAccessException e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw new ServiceUnavailableException("operations-service", e);
        } finally {
            span.end();
        }
    }

    public JobDto createJob(CreateJobRequest request) {
        Span span = tracer.spanBuilder("frontend.createJob")
                .setAttribute("downstream_service", "operations-service")
                .setAttribute("http.method", "POST")
                .setAttribute("http.url", baseUrl + "/api/jobs")
                .startSpan();
        try (Scope ignored = span.makeCurrent()) {
            log.debug("Creating job via operations-service: {}", request);
            return restClient.post()
                    .uri("/api/jobs")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(request)
                    .retrieve()
                    .body(JobDto.class);
        } catch (HttpStatusCodeException e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw new BackendException("operations-service", e.getStatusCode().value(), parseError(e));
        } catch (ResourceAccessException e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw new ServiceUnavailableException("operations-service", e);
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
