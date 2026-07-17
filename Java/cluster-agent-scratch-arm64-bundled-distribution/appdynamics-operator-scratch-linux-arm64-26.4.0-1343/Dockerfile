# Multi-stage build for scratch-based AppDynamics Operator
# Stage 1: Build stage using Alpine for setup
ARG version=latest
FROM alpine:$version AS builder

# Install required packages for setup
RUN apk --update add --no-cache ca-certificates && update-ca-certificates && \
    apk upgrade --no-cache && \
    rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

# Create user and group structure (for scratch image compatibility)
RUN addgroup -g 9001 appdynamics && \
    adduser -u 9001 -G appdynamics -s /bin/false -D appdynamics

# Create necessary directory structure
RUN mkdir -p /opt/appdynamics && \
    mkdir -p /opt/appdynamics/licenses && \
    mkdir -p /home/appdynamics && \
    chown appdynamics:appdynamics /home/appdynamics

# Copy the operator binary
COPY bin/appdynamics-operator /opt/appdynamics/appdynamics-operator

# Copy LICENSE
COPY LICENSE /opt/appdynamics/licenses/

# Set proper permissions
RUN chmod 755 /opt/appdynamics/appdynamics-operator && \
    chown -R appdynamics:appdynamics /opt/appdynamics

# Stage 2: Create the minimal scratch image
FROM scratch
ARG BUILD_DATE

LABEL org.opencontainers.image.title="AppDynamics Operator" \
      org.opencontainers.image.description="The Appdynamics Operator is used to install Cluster Agent & InfraViz" \
      org.opencontainers.image.version="26.4.0" \
      org.opencontainers.image.created=${BUILD_DATE} \
      org.opencontainers.image.vendor="AppDynamics" \
      org.opencontainers.image.url="https://www.appdynamics.com"

# Copy CA certificates from builder
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Copy shell and necessary libraries for script execution
COPY --from=builder /bin/sh /bin/sh
# Copy musl library (may vary by architecture)
COPY --from=builder /lib /lib

# Copy user/group information
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group

# Copy the operator binary from builder
COPY --from=builder /opt/appdynamics/appdynamics-operator /opt/appdynamics/appdynamics-operator

# Copy LICENSE
COPY --from=builder /opt/appdynamics/licenses /opt/appdynamics/licenses

# Copy home directory structure
COPY --from=builder /home/appdynamics /home/appdynamics

# Set environment variables
ENV USER_UID=9001 \
    USER_NAME=appdynamics \
    HOME=/home/appdynamics \
    OPERATOR=/opt/appdynamics/appdynamics-operator \
    PATH=/opt/appdynamics


# Use the non-root user (numeric UID required for Kubernetes runAsNonRoot verification)
USER ${USER_UID}

# Set working directory
WORKDIR ${HOME}

# Use the operator binary directly as entrypoint
ENTRYPOINT ["/opt/appdynamics/appdynamics-operator"]
