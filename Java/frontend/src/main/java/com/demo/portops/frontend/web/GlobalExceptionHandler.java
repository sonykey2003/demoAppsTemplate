package com.demo.portops.frontend.web;

import com.demo.portops.frontend.exception.BackendException;
import com.demo.portops.frontend.exception.ServiceUnavailableException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.servlet.ModelAndView;

import jakarta.servlet.http.HttpServletResponse;

@ControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(BackendException.class)
    public ModelAndView handleBackendException(BackendException ex, HttpServletResponse response) {
        log.warn("Backend error from {}: status={} message={}", ex.getServiceName(),
                ex.getStatusCode(), ex.getMessage());
        response.setStatus(ex.getStatusCode() >= 500 ? 502 : ex.getStatusCode());
        ModelAndView mav = new ModelAndView("error");
        mav.addObject("errorTitle", "Backend Service Error");
        mav.addObject("serviceName", ex.getServiceName());
        mav.addObject("statusCode", ex.getStatusCode());
        mav.addObject("errorMessage", ex.getMessage());
        mav.addObject("errorCode",
                ex.getErrorDetail() != null ? ex.getErrorDetail().code() : "BACKEND_ERROR");
        mav.addObject("traceId",
                ex.getErrorDetail() != null ? ex.getErrorDetail().traceId() : currentTraceId());
        return mav;
    }

    @ExceptionHandler(ServiceUnavailableException.class)
    public ModelAndView handleServiceUnavailable(ServiceUnavailableException ex,
                                                  HttpServletResponse response) {
        log.error("Service unavailable: {}", ex.getServiceName(), ex);
        response.setStatus(503);
        ModelAndView mav = new ModelAndView("error");
        mav.addObject("errorTitle", "Service Unavailable");
        mav.addObject("serviceName", ex.getServiceName());
        mav.addObject("statusCode", 503);
        mav.addObject("errorMessage", ex.getMessage());
        mav.addObject("errorCode", "SERVICE_UNAVAILABLE");
        mav.addObject("traceId", currentTraceId());
        return mav;
    }

    @ExceptionHandler(Exception.class)
    public ModelAndView handleGenericException(Exception ex, HttpServletResponse response) {
        log.error("Unhandled exception", ex);
        response.setStatus(500);
        ModelAndView mav = new ModelAndView("error");
        mav.addObject("errorTitle", "Internal Error");
        mav.addObject("serviceName", "frontend");
        mav.addObject("statusCode", 500);
        mav.addObject("errorMessage", ex.getMessage());
        mav.addObject("errorCode", "INTERNAL_ERROR");
        mav.addObject("traceId", currentTraceId());
        return mav;
    }

    private String currentTraceId() {
        String id = MDC.get("trace_id");
        return id != null ? id : "";
    }
}
