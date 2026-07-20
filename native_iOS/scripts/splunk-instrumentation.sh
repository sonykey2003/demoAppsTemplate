#!/usr/bin/env bash
# scripts/splunk-instrumentation.sh
# ─────────────────────────────────────────────────────────────────────────────
# One-shot, idempotent Splunk Observability Cloud instrumentation for the
# SEA Bank demo (traces + metrics for the Node.js services).
#
#   connect    Install the Splunk Distribution of the OTel Collector + Operator
#              (Helm) into a SEPARATE namespace (OTEL_NAMESPACE, default splunk-otel).
#   instrument Point the Node.js services (namespace APP_NAMESPACE=sea-bank-demo)
#              at the collector via zero-code auto-instrumentation (OTel Operator).
#   verify     Confirm collector pods are up and the Node agent is injected.
#   all        connect -> instrument -> verify.
#   status     Show current integration state.
#   uninstall  Remove instrumentation + the collector release.
#
# The collector lives in its own namespace; the OTel Operator is cluster-scoped, so
# it injects into sea-bank-demo pods via a cross-namespace "<otel-ns>/<name>" ref.
# Everything is tagged deployment.environment=shawn-rum.
#
# Needs SPLUNK_REALM + SPLUNK_ACCESS_TOKEN. Config comes from an env file
# (see scripts/splunk-integration.env.example). Secrets may be raw or 1Password
# refs (op://...), resolved via `op read`.
# Usage: ./scripts/splunk-instrumentation.sh <command> [--dry-run] [--env-file PATH]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/splunk-integration.env"

DRY_RUN=0
ENV_FILE="${SPLUNK_INTEGRATION_ENV_FILE:-${DEFAULT_ENV_FILE}}"

# Node.js services that get auto-instrumented.
NODE_SERVICES=(api-gateway auth-service account-service transfer-service)
INJECT_ANNOTATION="instrumentation.opentelemetry.io/inject-nodejs"
HELM_REPO_NAME="splunk-otel-collector-chart"
HELM_REPO_URL="https://signalfx.github.io/splunk-otel-collector-chart"
HELM_CHART="${HELM_REPO_NAME}/splunk-otel-collector"

c_reset=$'\033[0m'; c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_bold=$'\033[1m'
step() { printf '\n%s==> %s%s\n' "${c_bold}${c_blue}" "$*" "${c_reset}"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s✓ %s%s\n' "${c_green}" "$*" "${c_reset}"; }
warn() { printf '    %s! %s%s\n' "${c_yellow}" "$*" "${c_reset}" >&2; }
die()  { printf '%sError:%s %s\n' "${c_red}" "${c_reset}" "$*" >&2; exit 1; }

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

resolve_secret() {
  local v="${1:-}"
  if [[ "${v}" == op://* ]]; then
    command -v op >/dev/null 2>&1 || die "Value is a 1Password ref but 'op' CLI is not installed: ${v}"
    op read "${v}"
  else
    printf '%s' "${v}"
  fi
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

usage() {
  cat <<EOF
${c_bold}SEA Bank demo — Splunk Observability Cloud instrumentation (backend APM)${c_reset}

Usage: $(basename "$0") <command> [options]

Commands:
  connect      Install/upgrade the Splunk OTel Collector + Operator (Helm) in OTEL_NAMESPACE.
  instrument   Enable zero-code Node.js auto-instrumentation on the sea-bank-demo services.
  verify       Confirm collector pods are up and the Node agent is injected.
  all          connect -> instrument -> verify.
  status       Show current integration state.
  uninstall    Remove instrumentation + the collector release.
  help         Show this help.

Options:
  --dry-run            Print mutating commands without executing them.
  --env-file PATH      Source config from PATH (default: ${DEFAULT_ENV_FILE}).

Config: see scripts/splunk-integration.env.example.
EOF
}

load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    step "Loading config from ${ENV_FILE}"
    # shellcheck disable=SC1090
    set -a; source "${ENV_FILE}"; set +a
    ok "config loaded"
  else
    info "No env file at ${ENV_FILE} (using current environment)."
  fi

  # Defaults — collector deliberately in its OWN namespace, env tag = shawn-rum.
  CLUSTER_NAME="${CLUSTER_NAME:-sea-bank-demo}"
  ENVIRONMENT="${ENVIRONMENT:-shawn-rum}"
  APP_NAMESPACE="${APP_NAMESPACE:-sea-bank-demo}"
  OTEL_NAMESPACE="${OTEL_NAMESPACE:-splunk-otel}"
  HELM_RELEASE="${HELM_RELEASE:-splunk-otel-collector}"
  PROFILING_ENABLED="${PROFILING_ENABLED:-false}"
  DISCOVERY_ENABLED="${DISCOVERY_ENABLED:-true}"
  # OTel Operator webhook needs cert-manager. On a fresh cluster let the chart install it.
  CERTMANAGER_ENABLED="${CERTMANAGER_ENABLED:-true}"

  SPLUNK_ACCESS_TOKEN="$(resolve_secret "${SPLUNK_ACCESS_TOKEN:-}")"
}

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
  info "realm=${SPLUNK_REALM} cluster=${CLUSTER_NAME} env=${ENVIRONMENT}"
  info "collector ns=${OTEL_NAMESPACE}  app ns=${APP_NAMESPACE}"
  info "O11y access token: $(mask "${SPLUNK_ACCESS_TOKEN}")"

  ensure_helm_repo
  ensure_secret

  # Node agent env applied to the Operator Instrumentation CR.
  # OTEL_LOGS_EXPORTER=otlp makes the Node agent emit app logs through its OTLP log
  # pipeline so records carry service.name/deployment.environment/trace_id/span_id.
  local node_env_json
  node_env_json='[{"name":"OTEL_LOGS_EXPORTER","value":"otlp"}]'

  # Stamp deployment.environment on the agent's resource up front (not just via the
  # collector pipeline), so every signal is tagged shawn-rum.
  local node_resource_json
  node_resource_json='{"deployment.environment":"'"${ENVIRONMENT}"'"}'

  local set_args=(
    --namespace "${OTEL_NAMESPACE}" --create-namespace
    --set "clusterName=${CLUSTER_NAME}"
    --set "environment=${ENVIRONMENT}"
    --set "splunkObservability.realm=${SPLUNK_REALM}"
    --set "secret.create=false"
    --set "secret.name=${HELM_RELEASE}"
    --set "splunkObservability.metricsEnabled=true"
    --set "splunkObservability.tracesEnabled=true"
    --set "splunkObservability.profilingEnabled=${PROFILING_ENABLED}"
    --set "gateway.enabled=false"
    --set "agent.discovery.enabled=${DISCOVERY_ENABLED}"
    --set "operatorcrds.install=true"
    --set "operator.enabled=true"
    --set "certmanager.enabled=${CERTMANAGER_ENABLED}"
    --set "instrumentation.installationJob.enabled=true"
    --set-json "instrumentation.spec.nodejs.env=${node_env_json}"
    --set-json "instrumentation.spec.resource.resourceAttributes=${node_resource_json}"
  )

  # On re-runs the Operator and Helm fight over the Instrumentation CR's spec
  # (server-side-apply conflict). Delete it first so Helm recreates it cleanly.
  if [[ "${DRY_RUN}" -eq 0 ]] && helm status "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}" >/dev/null 2>&1; then
    run kubectl delete instrumentation "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}" --ignore-not-found
  fi

  run helm upgrade --install "${HELM_RELEASE}" "${HELM_CHART}" "${set_args[@]}" --wait --timeout 8m
  ok "Collector release '${HELM_RELEASE}' deployed in ${OTEL_NAMESPACE}."
}

instrumentation_ref() {
  # "<otel-ns>/<instrumentation-name>" so injection works across namespaces.
  local name
  name="$(kubectl get otelinst -n "${OTEL_NAMESPACE}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "${name}" ]] || name="${HELM_RELEASE}"
  printf '%s/%s' "${OTEL_NAMESPACE}" "${name}"
}

cmd_instrument() {
  require_cmd kubectl
  local ref; ref="$(instrumentation_ref)"
  step "Enabling Node.js auto-instrumentation (inject ${ref})"

  if ! kubectl get otelinst -n "${OTEL_NAMESPACE}" >/dev/null 2>&1; then
    warn "No Instrumentation CR found in ${OTEL_NAMESPACE}. Run 'connect' first."
  fi

  local svc
  for svc in "${NODE_SERVICES[@]}"; do
    if ! kubectl get deployment "${svc}" -n "${APP_NAMESPACE}" >/dev/null 2>&1; then
      warn "Deployment ${svc} not found in ${APP_NAMESPACE}; skipping."
      continue
    fi
    run kubectl patch deployment "${svc}" -n "${APP_NAMESPACE}" --type merge \
      -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"${INJECT_ANNOTATION}\":\"${ref}\"}}}}}"
    ok "Annotated ${svc}."
  done

  step "Rolling out instrumented services"
  for svc in "${NODE_SERVICES[@]}"; do
    kubectl get deployment "${svc}" -n "${APP_NAMESPACE}" >/dev/null 2>&1 || continue
    run kubectl rollout status "deployment/${svc}" -n "${APP_NAMESPACE}" --timeout=180s
  done
  ok "Node services pointed at the collector via the operator."
}

cmd_verify() {
  require_cmd kubectl
  step "Collector pods in ${OTEL_NAMESPACE}"
  kubectl get pods -n "${OTEL_NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" 2>/dev/null || \
    kubectl get pods -n "${OTEL_NAMESPACE}"

  step "Instrumentation CR"
  kubectl get otelinst -n "${OTEL_NAMESPACE}" 2>/dev/null || warn "No Instrumentation CR found."

  step "Node agent injection check (api-gateway)"
  if kubectl get deployment api-gateway -n "${APP_NAMESPACE}" >/dev/null 2>&1; then
    kubectl exec "deployment/api-gateway" -n "${APP_NAMESPACE}" -- env 2>/dev/null \
      | grep -E 'NODE_OPTIONS|OTEL_EXPORTER_OTLP_ENDPOINT|OTEL_SERVICE_NAME|OTEL_RESOURCE_ATTRIBUTES' \
      || warn "No agent env found yet — pods may still be restarting."
  else
    warn "api-gateway not found in ${APP_NAMESPACE}."
  fi
}

cmd_status() {
  require_cmd kubectl
  step "Integration status"
  info "Realm:        ${SPLUNK_REALM:-<unset>}"
  info "Cluster/env:  ${CLUSTER_NAME} / ${ENVIRONMENT}"
  info "Collector ns: ${OTEL_NAMESPACE}   App ns: ${APP_NAMESPACE}"

  helm status "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}" >/dev/null 2>&1 \
    && ok "Helm release '${HELM_RELEASE}' present." || warn "Helm release '${HELM_RELEASE}' not installed."

  local svc
  for svc in "${NODE_SERVICES[@]}"; do
    local val
    val="$(kubectl get deployment "${svc}" -n "${APP_NAMESPACE}" \
      -o jsonpath="{.spec.template.metadata.annotations.${INJECT_ANNOTATION//./\\.}}" 2>/dev/null || true)"
    [[ -n "${val}" ]] && ok "${svc}: inject-nodejs=${val}" || warn "${svc}: not instrumented"
  done
}

cmd_uninstall() {
  require_cmd kubectl; require_cmd helm
  step "Removing Node.js auto-instrumentation annotations"
  local svc
  for svc in "${NODE_SERVICES[@]}"; do
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

main() {
  local cmd="${1:-help}"; shift || true
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --env-file) shift; ENV_FILE="${1:?--env-file needs a path}" ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done

  case "${cmd}" in help|-h|--help) usage; exit 0 ;; esac

  load_env

  case "${cmd}" in
    connect)    cmd_connect ;;
    instrument) cmd_instrument ;;
    verify)     cmd_verify ;;
    status)     cmd_status ;;
    uninstall)  cmd_uninstall ;;
    all)        cmd_connect; cmd_instrument; cmd_verify
                step "Done — Splunk O11y APM"
                info "Generate traffic (./scripts/load-generator.sh --scenario mixed) and open"
                info "APM in Splunk O11y, filtered to environment '${ENVIRONMENT}'." ;;
    *) usage; die "Unknown command: ${cmd}" ;;
  esac
}

main "$@"
