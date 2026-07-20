# Backend Observability (APM) — detached / console-managed

This repo deploys **only application workloads**. It ships no OpenTelemetry SDK, no agents,
no exporters, and no ingest tokens. The services emit custom spans/metrics through the
**OpenTelemetry API**, which stays a no-op until you attach a real SDK/agent out of band.
Everything is tagged with `deployment.environment = shawn-rum`.

You pick the platform: **Splunk Observability Cloud** or **AppDynamics**.

---

## Option A — Splunk Observability Cloud (OpenTelemetry)

Use the **OpenTelemetry Operator** auto-instrumentation for Node.js, or the Splunk OTel
Collector chart's operator, to inject `splunk-otel-js` via `NODE_OPTIONS` — no image changes.

1. Install the Splunk OTel Collector + Operator (from the Splunk O11y console / Helm).
2. Create an `Instrumentation` CR for Node.js and annotate the `sea-bank-demo` namespace or
   the deployments, e.g.:
   ```yaml
   metadata:
     annotations:
       instrumentation.opentelemetry.io/inject-nodejs: "true"
   ```
3. Ensure resource attributes carry the environment tag:
   ```yaml
   spec:
     nodejs:
       env:
         - name: OTEL_RESOURCE_ATTRIBUTES
           value: "deployment.environment=shawn-rum"
         - name: OTEL_LOGS_EXPORTER      # trace-correlated logs (optional)
           value: otlp
   ```
4. Restart the deployments. `service.name` is derived from the workload; custom spans
   (`transfer.create`, `account.balance_fetch`, …) and metrics appear automatically.

## Option B — AppDynamics (Node.js agent)

Inject the AppDynamics Node.js agent out of band (init container / `NODE_OPTIONS=-r appdynamics`
or the AppDynamics Operator). Set the controller/app/tier and environment to `shawn-rum`.
The OpenTelemetry-API custom spans surface as exit/entry calls and business transactions per
the agent's OTel bridge; the HTTP fan-out (gateway → services → account-service) shows the
distributed flow.

---

## What to show

- **Service map / flow map**: app → api-gateway → {auth, account, transfer} → account-service.
- **A transfer trace**: `transfer.create` → validate ×2 → async `transfer.settle` → debit/credit.
- **Latency spike**: `./scripts/fault-inject.sh latency 2000` then watch p95 climb.
- **Error rate**: `./scripts/fault-inject.sh error 0.5` then watch the error % and failed spans.
- **Metrics**: `transfer_created_total`, `account_balance_requests_total{cache}`, `transfer_queue_depth`.

## Trace-correlated logs

Logs are single-line JSON with `trace_id`/`span_id` already present (when an SDK is attached).
To make them queryable + trace-linked you must **export logs through the agent's pipeline**
(e.g. Splunk OTel `OTEL_LOGS_EXPORTER=otlp`). Collecting container stdout alone does not carry
trace context. See the Java demo's `scripts/splunk-logs.sh` for the Log Observer Connect path.

## RUM ↔ APM correlation

The mobile RUM SDK instruments the app's network calls and, when configured, propagates
`traceparent` on the gateway requests — linking a RUM session/interaction to the backend trace.
See [RUM.md](RUM.md).
