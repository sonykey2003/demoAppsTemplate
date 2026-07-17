# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /build
ARG MAVEN_PROFILES=""
COPY pom.xml .
COPY src ./src
RUN if [ -n "${MAVEN_PROFILES}" ]; then \
      mvn -B -DskipTests -P"${MAVEN_PROFILES}" package; \
    else \
      mvn -B -DskipTests package; \
    fi

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre AS runtime
RUN useradd -u 10001 -r -s /usr/sbin/nologin appuser
WORKDIR /app
COPY --from=builder /build/target/operations-service-0.1.0.jar /app/app.jar
RUN chown appuser:0 /app/app.jar
USER 10001
EXPOSE 9083
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:9083/healthz || exit 1
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
