package com.demo.portops.operations.dto;

public class ErrorResponse {

    private final ErrorBody error;

    public ErrorResponse(String code, String message, String traceId) {
        this.error = new ErrorBody(code, message, traceId);
    }

    public ErrorBody getError() { return error; }

    public static class ErrorBody {
        private final String code;
        private final String message;
        private final String traceId;

        public ErrorBody(String code, String message, String traceId) {
            this.code = code;
            this.message = message;
            this.traceId = traceId;
        }

        public String getCode() { return code; }
        public String getMessage() { return message; }

        @com.fasterxml.jackson.annotation.JsonProperty("trace_id")
        public String getTraceId() { return traceId; }
    }
}
