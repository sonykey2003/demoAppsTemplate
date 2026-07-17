#!/usr/bin/env bash
# scripts/splunk-instrumentation.sh
# ─────────────────────────────────────────────────────────────────────────────
# One-shot, idempotent Splunk Observability Cloud instrumentation for
# port-ops-demo (traces, metrics, profiling; Secure Application optional).
#
#   connect    Install the Splunk Distribution of the OTel Collector (Helm)
#   instrument Point the Java services at the collector via zero-code
#              auto-instrumentation (OpenTelemetry Operator)
#
# Needs only SPLUNK_REALM + SPLUNK_ACCESS_TOKEN — no Splunk Cloud stack. Add
# `--secure-app` (or SECURE_APP_ENABLED=true) to turn on Splunk Secure Application.
#
# Trace-correlated logs via Splunk Cloud Platform / Log Observer Connect are an
# OPTIONAL, separate step handled by scripts/splunk-logs.sh (run this script first).
#
# Every command is safe to re-run. Use `uninstall` to detach cleanly.
#
# Config comes from environment variables — see scripts/splunk-integration.env.example.
# Secrets may be raw values or 1Password refs (op://...), resolved via `op read`.
# Usage: ./scripts/splunk-instrumentation.sh <command> [--secure-app] [--dry-run] [--env-file PATH]
set -euo pipefail

# ── Paths / defaults ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/splunk-integration.env"

DRY_RUN=0
SECURE_APP_FLAG=0
ENV_FILE="${SPLUNK_INTEGRATION_ENV_FILE:-${DEFAULT_ENV_FILE}}"

# Java services that get auto-instrumented (postgres/redis are skipped).
JAVA_SERVICES=(frontend vessel-service container-service operations-service)
INJECT_ANNOTATION="instrumentation.opentelemetry.io/inject-java"
HELM_REPO_NAME="splunk-otel-collector-chart"
HELM_REPO_URL="https://signalfx.github.io/splunk-otel-collector-chart"
HELM_CHART="${HELM_REPO_NAME}/splunk-otel-collector"

# ── Logging ──────────────────────────────────────────────────────────────────
c_reset=$'\033[0m'; c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_bold=$'\033[1m'
step() { printf '\n%s==> %s%s\n' "${c_bold}${c_blue}" "$*" "${c_reset}"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s✓ %s%s\n' "${c_green}" "$*" "${c_reset}"; }
warn() { printf '    %s! %s%s\n' "${c_yellow}" "$*" "${c_reset}" >&2; }
die()  { printf '%sError:%s %s\n' "${c_red}" "${c_reset}" "$*" >&2; exit 1; }

# Print a command then run it (skipped in dry-run for mutating ops).
run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '    %s[dry-run]%s %s\n' "${c_yellow}" "${c_reset}" "$*"
    return 0
  fi
  "$@"
}

mask() {
  local v="$1"
  if [[ -z "${v}" ]]; then printf '<unset>'; elif [[ "${#v}" -le 8 ]]; then printf '****'; else printf '****%s' "${v: -4}"; fi
}

# Resolve a value that may be a 1Password reference.
resolve_secret() {
  local v="${1:-}"
  if [[ "${v}" == op://* ]]; then
    command -v op >/dev/null 2>&1 || die "Value is a 1Password ref but 'op' CLI is not installed: ${v}"
    op read "${v}"
  else
    printf '%s' "${v}"
  fi
}

usage() {
  cat <<EOF
${c_bold}port-ops-demo Splunk Observability Cloud integration${c_reset}

Usage: $(basename "$0") <command> [options]

Commands:
  connect      Install/upgrade the Splunk Distribution of the OTel Collector (Helm).
  instrument   Enable zero-code Java auto-instrumentation on the app deployments.
  verify       Confirm collector pods are up and the Java agent is injected.
  all          connect -> instrument -> verify.
  status       Show current integration state.
  uninstall    Remove instrumentation + the collector release.
  help         Show this help.

Options:
  --secure-app         Enable Splunk Secure Application (default: off).
  --dry-run            Print mutating commands without executing them.
  --env-file PATH      Source config from PATH (default: ${DEFAULT_ENV_FILE}).

Optional trace-correlated logs (Splunk Cloud Platform / Log Observer Connect) are a
separate step — see scripts/splunk-logs.sh.

Config: environment variables (see scripts/splunk-integration.env.example).
EOF
}

# ── Env handling ─────────────────────────────────────────────────────────────
load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    step "Loading config from ${ENV_FILE}"
    # shellcheck disable=SC1090
    set -a; source "${ENV_FILE}"; set +a
    ok "config loaded"
  else
    info "No env file at ${ENV_FILE} (using current environment)."
  fi

  # Defaults
  CLUSTER_NAME="${CLUSTER_NAME:-port-ops-demo}"
  ENVIRONMENT="${ENVIRONMENT:-port-ops-demo}"
  APP_NAMESPACE="${APP_NAMESPACE:-port-ops-demo}"
  OTEL_NAMESPACE="${OTEL_NAMESPACE:-port-ops-demo}"
  HELM_RELEASE="${HELM_RELEASE:-splunk-otel-collector}"
  PROFILING_ENABLED="${PROFILING_ENABLED:-true}"
  DISCOVERY_ENABLED="${DISCOVERY_ENABLED:-true}"
  # Secure Application is opt-in: --secure-app flag or SECURE_APP_ENABLED=true.
  SECURE_APP_ENABLED="${SECURE_APP_ENABLED:-false}"
  [[ "${SECURE_APP_FLAG}" -eq 1 ]] && SECURE_APP_ENABLED="true"

  # Resolve secrets (supports op:// refs).
  SPLUNK_ACCESS_TOKEN="$(resolve_secret "${SPLUNK_ACCESS_TOKEN:-}")"
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

# ── Command: connect ─────────────────────────────────────────────────────────
ensure_helm_repo() {
  if ! helm repo list 2>/dev/null | grep -q "^${HELM_REPO_NAME}[[:space:]]"; then
    run helm repo add "${HELM_REPO_NAME}" "${HELM_REPO_URL}"
  fi
  run helm repo update "${HELM_REPO_NAME}" >/dev/null
}

# Create the chart secret so the token never appears in `helm get values`.
ensure_secret() {
  local args=(create secret generic "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}"
    --from-literal=splunk_observability_access_token="${SPLUNK_ACCESS_TOKEN}")
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '    %s[dry-run]%s kubectl create namespace %s (idempotent)\n' "${c_yellow}" "${c_reset}" "${OTEL_NAMESPACE}"
    printf '    %s[dry-run]%s kubectl %s --dry-run=client -o yaml | kubectl apply -f -\n' \
      "${c_yellow}" "${c_reset}" "${args[*]//${SPLUNK_ACCESS_TOKEN}/$(mask "${SPLUNK_ACCESS_TOKEN}")}"
    return 0
  fi
  kubectl create namespace "${OTEL_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl "${args[@]}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  ok "Secret '${HELM_RELEASE}' ensured in namespace ${OTEL_NAMESPACE}."
}

cmd_connect() {
  require_cmd kubectl; require_cmd helm
  [[ -n "${SPLUNK_REALM:-}" ]] || die "SPLUNK_REALM is required (e.g. us1)."
  [[ -n "${SPLUNK_ACCESS_TOKEN}" ]] || die "SPLUNK_ACCESS_TOKEN (O11y) is required."

  step "Installing Splunk Distribution of the OpenTelemetry Collector"
  info "realm=${SPLUNK_REALM} cluster=${CLUSTER_NAME} env=${ENVIRONMENT} ns=${OTEL_NAMESPACE}"
  info "O11y access token: $(mask "${SPLUNK_ACCESS_TOKEN}")  secure-app=${SECURE_APP_ENABLED}"

  ensure_helm_repo
  ensure_secret

  # Java agent env applied to the Operator Instrumentation CR.
  # OTEL_LOGS_EXPORTER=otlp is the crucial setting: it makes the Java agent emit
  # application logs through its OTLP log pipeline, so each record carries
  # service.name, deployment.environment, trace_id and span_id. Those correlated
  # logs feed O11y native logs and, if you later run scripts/splunk-logs.sh, the
  # APM "Related Logs" tab via Log Observer Connect. Container stdout collection
  # alone does NOT trace-correlate. The logback appender experimental flag forwards
  # MDC values (terminal_id, vessel_code, …) as log attributes. Helm replaces list
  # values on merge, so the chart's default java env entries are restated here
  # alongside the two log-export entries.
  #
  local java_env_json
  java_env_json='[{"name":"OTEL_RESOURCE_DISABLED_KEYS","value":"process.executable.path,process.command_args"},{"name":"OTEL_JAVA_ENABLED_RESOURCE_PROVIDERS","value":"io.opentelemetry.instrumentation.resources.ContainerResourceProvider,io.opentelemetry.sdk.autoconfigure.EnvironmentResourceProvider,io.opentelemetry.instrumentation.resources.ProcessResourceProvider"},{"name":"OTEL_LOGS_EXPORTER","value":"otlp"},{"name":"OTEL_INSTRUMENTATION_LOGBACK_APPENDER_EXPERIMENTAL_LOG_ATTRIBUTES","value":"true"}]'

  # deployment.environment MUST be stamped on the agent's resource, not just by the
  # collector. The chart's traces/logs collector pipelines run a resource/add_environment
  # processor, but the logs/secureapp pipeline does NOT — so Splunk Application Security
  # (Secure App) findings would otherwise ship with no deployment.environment and never
  # appear under the environment filter in the App Security UI. Setting it via the
  # operator's spec.resource.resourceAttributes makes the CSA agent tag every signal
  # (traces, logs, secure-app events) with deployment.environment up front. This uses the
  # operator's merge path (no collision with the chart-injected OTEL_RESOURCE_ATTRIBUTES).
  local java_resource_json
  java_resource_json='{"deployment.environment":"'"${ENVIRONMENT}"'"}'

  local set_args=(
    --namespace "${OTEL_NAMESPACE}" --create-namespace
    --set "clusterName=${CLUSTER_NAME}"
    --set "environment=${ENVIRONMENT}"
    --set "splunkObservability.realm=${SPLUNK_REALM}"
    --set "secret.create=false"
    --set "secret.name=${HELM_RELEASE}"
    --set "splunkObservability.metricsEnabled=true"
    --set "splunkObservability.tracesEnabled=true"
    # NOTE: splunk-otel-collector chart 0.153.x has NO splunkObservability.logsEnabled
    # key (the schema rejects it). Native O11y log ingest happens automatically over
    # the OTLP logs pipeline once the Java agent exports logs via OTEL_LOGS_EXPORTER=otlp
    # (set on instrumentation.spec.java.env below).
    --set "splunkObservability.profilingEnabled=${PROFILING_ENABLED}"
    --set "splunkObservability.secureAppEnabled=${SECURE_APP_ENABLED}"
    --set "gateway.enabled=false"
    --set "agent.discovery.enabled=${DISCOVERY_ENABLED}"
    --set "operatorcrds.install=true"
    --set "operator.enabled=true"
    --set "instrumentation.installationJob.enabled=true"
    --set-json "instrumentation.spec.java.env=${java_env_json}"
    --set-json "instrumentation.spec.resource.resourceAttributes=${java_resource_json}"
  )

  # On re-runs, the Operator and Helm fight over ownership of the Instrumentation
  # CR's spec.java.env (server-side-apply field-manager conflict), which fails the
  # upgrade. Deleting the CR first lets Helm recreate it cleanly; already-injected
  # app pods keep running until their next rollout.
  if [[ "${DRY_RUN}" -eq 0 ]] && helm status "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}" >/dev/null 2>&1; then
    run kubectl delete instrumentation "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}" --ignore-not-found
  fi

  run helm upgrade --install "${HELM_RELEASE}" "${HELM_CHART}" "${set_args[@]}" --wait --timeout 8m
  ok "Collector release '${HELM_RELEASE}' deployed."
}

# ── Command: instrument ──────────────────────────────────────────────────────
instrumentation_ref() {
  # Returns "<otel-ns>/<instrumentation-name>" so it works cross-namespace.
  local name
  name="$(kubectl get otelinst -n "${OTEL_NAMESPACE}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "${name}" ]] || name="${HELM_RELEASE}"
  printf '%s/%s' "${OTEL_NAMESPACE}" "${name}"
}

cmd_instrument() {
  require_cmd kubectl
  local ref; ref="$(instrumentation_ref)"
  step "Enabling Java auto-instrumentation (inject ${ref})"

  if ! kubectl get otelinst -n "${OTEL_NAMESPACE}" >/dev/null 2>&1; then
    warn "No Instrumentation CR found in ${OTEL_NAMESPACE}. Run 'connect' first."
  fi

  local svc
  for svc in "${JAVA_SERVICES[@]}"; do
    if ! kubectl get deployment "${svc}" -n "${APP_NAMESPACE}" >/dev/null 2>&1; then
      warn "Deployment ${svc} not found in ${APP_NAMESPACE}; skipping."
      continue
    fi
    run kubectl patch deployment "${svc}" -n "${APP_NAMESPACE}" --type merge \
      -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"${INJECT_ANNOTATION}\":\"${ref}\"}}}}}"
    ok "Annotated ${svc}."
  done

  step "Rolling out instrumented services"
  for svc in "${JAVA_SERVICES[@]}"; do
    kubectl get deployment "${svc}" -n "${APP_NAMESPACE}" >/dev/null 2>&1 || continue
    run kubectl rollout status "deployment/${svc}" -n "${APP_NAMESPACE}" --timeout=180s
  done
  ok "Java services pointed at the collector via the operator."
}

# ── Command: verify ──────────────────────────────────────────────────────────
cmd_verify() {
  require_cmd kubectl
  step "Collector pods in ${OTEL_NAMESPACE}"
  kubectl get pods -n "${OTEL_NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" 2>/dev/null || \
    kubectl get pods -n "${OTEL_NAMESPACE}"

  step "Instrumentation CR"
  kubectl get otelinst -n "${OTEL_NAMESPACE}" 2>/dev/null || warn "No Instrumentation CR found."

  step "Java agent injection check (operations-service)"
  if kubectl get deployment operations-service -n "${APP_NAMESPACE}" >/dev/null 2>&1; then
    kubectl exec "deployment/operations-service" -n "${APP_NAMESPACE}" -- env 2>/dev/null \
      | grep -E 'JAVA_TOOL_OPTIONS|OTEL_EXPORTER_OTLP_ENDPOINT|OTEL_SERVICE_NAME' \
      || warn "No agent env found yet — pods may still be restarting."
  else
    warn "operations-service not found in ${APP_NAMESPACE}."
  fi
}

# ── Command: status ──────────────────────────────────────────────────────────
cmd_status() {
  require_cmd kubectl
  step "Integration status"
  info "Realm:        ${SPLUNK_REALM:-<unset>}"
  info "Cluster/env:  ${CLUSTER_NAME} / ${ENVIRONMENT}"
  info "Collector ns: ${OTEL_NAMESPACE}   App ns: ${APP_NAMESPACE}"
  info "Secure App:   ${SECURE_APP_ENABLED}"

  helm status "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}" >/dev/null 2>&1 \
    && ok "Helm release '${HELM_RELEASE}' present." || warn "Helm release '${HELM_RELEASE}' not installed."

  local svc
  for svc in "${JAVA_SERVICES[@]}"; do
    local val
    val="$(kubectl get deployment "${svc}" -n "${APP_NAMESPACE}" \
      -o jsonpath="{.spec.template.metadata.annotations.${INJECT_ANNOTATION//./\\.}}" 2>/dev/null || true)"
    [[ -n "${val}" ]] && ok "${svc}: inject-java=${val}" || warn "${svc}: not instrumented"
  done
}

# ── Command: uninstall ───────────────────────────────────────────────────────
cmd_uninstall() {
  require_cmd kubectl; require_cmd helm
  step "Removing Java auto-instrumentation annotations"
  local svc
  for svc in "${JAVA_SERVICES[@]}"; do
    kubectl get deployment "${svc}" -n "${APP_NAMESPACE}" >/dev/null 2>&1 || continue
    run kubectl patch deployment "${svc}" -n "${APP_NAMESPACE}" --type merge \
      -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"${INJECT_ANNOTATION}\":null}}}}}"
    ok "Cleared annotation on ${svc}."
  done

  step "Deleting Instrumentation CR + Helm release"
  run kubectl delete otelinst -n "${OTEL_NAMESPACE}" --all --ignore-not-found=true
  run helm uninstall "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}" || true
  run kubectl delete secret "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}" --ignore-not-found=true
  ok "Detached. Re-run 'all' to re-integrate."
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
main() {
  local cmd="${1:-help}"; shift || true
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --secure-app) SECURE_APP_FLAG=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --env-file) shift; ENV_FILE="${1:?--env-file needs a path}" ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done

  case "${cmd}" in
    help|-h|--help) usage; exit 0 ;;
  esac

  load_env

  case "${cmd}" in
    connect)    cmd_connect ;;
    instrument) cmd_instrument ;;
    verify)     cmd_verify ;;
    status)     cmd_status ;;
    uninstall)  cmd_uninstall ;;
    all)
      cmd_connect
      cmd_instrument
      cmd_verify
      step "Done"
      info "Splunk Observability Cloud integration complete (traces/metrics/profiling -> env ${ENVIRONMENT})."
      info "Secure Application: ${SECURE_APP_ENABLED}."
      info "Optional trace-correlated logs (Log Observer Connect): ./scripts/splunk-logs.sh all"
      ;;
    *) usage; die "Unknown command: ${cmd}" ;;
  esac
}

main "$@"
