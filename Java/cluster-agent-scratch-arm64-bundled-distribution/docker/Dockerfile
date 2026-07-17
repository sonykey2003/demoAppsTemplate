# Multi-stage build for scratch-based AppDynamics Cluster Agent
# Stage 1: Build stage using Alpine for setup
ARG version=latest
FROM alpine:$version AS builder

# Install required packages for setup
RUN apk --update add --no-cache ca-certificates && update-ca-certificates && \
    apk upgrade --no-cache && \
    rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

# Create the required directory structure and files in builder stage
ENV CLUSTER_AGENT_HOME=/opt/appdynamics/cluster-agent/

# Copy cluster-agent.zip and extract it
COPY cluster-agent.zip /tmp/cluster-agent.zip
RUN mkdir -p ${CLUSTER_AGENT_HOME} && \
    unzip -oq /tmp/cluster-agent.zip -d ${CLUSTER_AGENT_HOME} && \
    rm /tmp/cluster-agent.zip

# Create the directory structure and symlinks needed by the application
RUN rm -rf /opt/appdynamics/cluster-agent/config/agent-monitoring.yml && \
    rm -rf /opt/appdynamics/cluster-agent/config/instrumentation.yml && \
    mkdir -p /opt/appdynamics/cluster-agent/config/agent-monitoring && \
    touch /opt/appdynamics/cluster-agent/config/agent-monitoring/agent-monitoring.yml && \
    ln -s /opt/appdynamics/cluster-agent/config/agent-monitoring/agent-monitoring.yml /opt/appdynamics/cluster-agent/config/agent-monitoring.yml && \
    mkdir -p /opt/appdynamics/cluster-agent/config/instrumentation && \
    touch /opt/appdynamics/cluster-agent/config/instrumentation/instrumentation.yml && \
    ln -s /opt/appdynamics/cluster-agent/config/instrumentation/instrumentation.yml /opt/appdynamics/cluster-agent/config/instrumentation.yml && \
    mkdir -p /opt/appdynamics/cluster-agent/config/target-allocator && \
    touch /opt/appdynamics/cluster-agent/config/target-allocator/config.yml && \
    ln -s /opt/appdynamics/cluster-agent/config/target-allocator/config.yml /opt/appdynamics/cluster-agent/config/target-allocator.yml

# Create logs directory
RUN mkdir -p /opt/appdynamics/cluster-agent/logs

# Create user and group structure (for scratch image compatibility)
RUN addgroup -g 9001 appdynamics && \
    adduser -u 9001 -G appdynamics -s /bin/false -D appdynamics

# Set proper permissions
RUN chown -R appdynamics:appdynamics /opt/appdynamics && \
    chmod -R 755 /opt/appdynamics

# Copy the start-appdynamics script (consistent with other images)
COPY start-appdynamics ${CLUSTER_AGENT_HOME}
RUN chmod 744 /opt/appdynamics/cluster-agent/start-appdynamics

# Stage 2: Create the minimal scratch image
FROM scratch

LABEL name="AppDynamics Cluster Agent" \
      vendor="AppDynamics" \
      title="AppDynamics Cluster Agent" \
      vendor="AppDynamics" \
      version="26.4.0" \
      release="1" \
      url="https://www.appdynamics.com" \
      summary="AppDynamics monitoring solution for applications deployed to Kubernetes clusters" \
      description="The ClusterAgent monitors state of Kubernetes or openshift resources and derives metrics to provide visibility into common application impacting issues."

# Copy CA certificates from builder
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Copy shell and necessary libraries for script execution
COPY --from=builder /bin/sh /bin/sh
COPY --from=builder /bin/cat /bin/cat
# Copy musl library (may vary by architecture)
COPY --from=builder /lib /lib

# Copy the entire application directory structure from builder
# Using --chmod to ensure execute permissions are preserved
COPY --from=builder --chmod=755 /opt/appdynamics /opt/appdynamics

# Copy user/group information for user 9001
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group

# Copy LICENSE
COPY LICENSE /licenses/

# Set environment
ENV CLUSTER_AGENT_HOME=/opt/appdynamics/cluster-agent/

# Use the non-root user (numeric UID required for Kubernetes runAsNonRoot verification)
USER 9001

# Set working directory
WORKDIR ${CLUSTER_AGENT_HOME}

# Use the start-appdynamics script (consistent with other images)
ENTRYPOINT ["/bin/sh"]
CMD ["-c", "./start-appdynamics"]
