package com.demo.portops.frontend.exception;

public class ServiceUnavailableException extends RuntimeException {

    private final String serviceName;

    public ServiceUnavailableException(String serviceName, Throwable cause) {
        super("Service unavailable: " + serviceName, cause);
        this.serviceName = serviceName;
    }

    public String getServiceName() { return serviceName; }
}
