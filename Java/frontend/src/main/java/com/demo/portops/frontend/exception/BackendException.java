package com.demo.portops.frontend.exception;

import com.demo.portops.frontend.dto.ErrorDetail;

public class BackendException extends RuntimeException {

    private final String serviceName;
    private final int statusCode;
    private final ErrorDetail errorDetail;

    public BackendException(String serviceName, int statusCode, ErrorDetail errorDetail) {
        super(errorDetail != null ? errorDetail.message() : "Backend error " + statusCode);
        this.serviceName = serviceName;
        this.statusCode = statusCode;
        this.errorDetail = errorDetail;
    }

    public String getServiceName() { return serviceName; }

    public int getStatusCode() { return statusCode; }

    public ErrorDetail getErrorDetail() { return errorDetail; }
}
