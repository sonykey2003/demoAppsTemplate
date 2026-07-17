#!/usr/bin/env bash
# scripts/splunk-logs.sh
# ─────────────────────────────────────────────────────────────────────────────
# OPTIONAL: trace-correlated logs for port-ops-demo via Splunk Cloud Platform +
# Log Observer Connect (LOC). This is a separate, optional layer on top of the
# base Splunk Observability Cloud instrumentation installed by
# scripts/splunk-instrumentation.sh — run that first.
#
#   index    Create the Splunk Cloud Platform index for this app   (ACS API)
#   hec      Create/fetch a HEC token scoped to that index         (ACS API)
#   enable   Add the platform-logs export to the existing collector (Helm upgrade)
#   verify   Confirm each log export leg is shipping records
#   disable  Turn the platform-logs export back off
#
# Needs the collector already installed by splunk-instrumentation.sh (release
# HELM_RELEASE in OTEL_NAMESPACE). The log forwarder itself only needs a HEC token
# (SPLUNK_HEC_TOKEN) + endpoint (SPLUNK_HEC_URL, or derived from SPLUNK_STACK).
# SPLUNK_STACK + SPLUNK_ACS_TOKEN are ONLY needed for the 'index'/'hec' ACS steps
# that auto-provision those on Splunk Cloud; supply your own HEC token to skip them.
#
# Shares scripts/splunk-integration.env with splunk-instrumentation.sh. Secrets may be
# raw values or 1Password refs (op://...), resolved via `op read`.
# Usage: ./scripts/splunk-logs.sh <command> [--dry-run] [--env-file PATH]
set -euo pipefail

# ── Paths / defaults ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/splunk-integration.env"

DRY_RUN=0
ENV_FILE="${SPLUNK_INTEGRATION_ENV_FILE:-${DEFAULT_ENV_FILE}}"

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

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

usage() {
  cat <<EOF
${c_bold}port-ops-demo Splunk Cloud logs (Log Observer Connect)${c_reset}

Optional layer on top of ./scripts/splunk-instrumentation.sh — install the O11y
collector with that script first, then use this one to ship trace-correlated
app logs to Splunk Cloud Platform for Log Observer Connect.

Usage: $(basename "$0") <command> [options]

Commands:
  index      Create the Splunk Cloud Platform index (ACS API).
  hec        Create/fetch a HEC token scoped to the index (ACS API).
  enable     Add the platform-logs export to the existing collector (Helm upgrade).
  verify     Confirm each log export leg is shipping records + print spot-checks.
  disable    Turn the platform-logs export back off (O11y is untouched).
  all        index -> hec -> enable -> verify (skips index+hec if SPLUNK_HEC_TOKEN is set).
  status     Show the current platform-logs state.
  help       Show this help.

Options:
  --dry-run            Print mutating commands without executing them.
  --env-file PATH      Source config from PATH (default: ${DEFAULT_ENV_FILE}).

Config: environment variables (see scripts/splunk-integration.env.example,
"Splunk Cloud Platform" section).
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
  SPLUNK_INDEX="${SPLUNK_INDEX:-port_ops_demo}"
  SPLUNK_INDEX_SEARCHABLE_DAYS="${SPLUNK_INDEX_SEARCHABLE_DAYS:-90}"
  SPLUNK_INDEX_MAX_SIZE_MB="${SPLUNK_INDEX_MAX_SIZE_MB:-0}"
  SPLUNK_HEC_NAME="${SPLUNK_HEC_NAME:-port-ops-demo-hec}"
  SPLUNK_HEC_URL="${SPLUNK_HEC_URL:-}"
  ENVIRONMENT="${ENVIRONMENT:-port-ops-demo}"
  OTEL_NAMESPACE="${OTEL_NAMESPACE:-port-ops-demo}"
  HELM_RELEASE="${HELM_RELEASE:-splunk-otel-collector}"

  # Resolve secrets (supports op:// refs).
  SPLUNK_ACS_TOKEN="$(resolve_secret "${SPLUNK_ACS_TOKEN:-}")"
  SPLUNK_ACCESS_TOKEN="$(resolve_secret "${SPLUNK_ACCESS_TOKEN:-}")"
  SPLUNK_HEC_TOKEN="$(resolve_secret "${SPLUNK_HEC_TOKEN:-}")"
}

# ── ACS (Splunk Cloud Platform admin API) ────────────────────────────────────
acs_base() { printf 'https://admin.splunk.com/%s/adminconfig/v2' "${SPLUNK_STACK}"; }

derive_hec_url() {
  if [[ -n "${SPLUNK_HEC_URL}" ]]; then printf '%s' "${SPLUNK_HEC_URL}"; return; fi
  [[ -n "${SPLUNK_STACK:-}" ]] || die "Set SPLUNK_HEC_URL or SPLUNK_STACK to derive the HEC endpoint."
  printf 'https://http-inputs-%s.splunkcloud.com/services/collector' "${SPLUNK_STACK}"
}

# curl wrapper for ACS: prints "<body>\n<http_code>".
acs_curl() {
  local method="$1" path="$2" data="${3:-}"
  local url; url="$(acs_base)${path}"
  local args=(-sS -X "${method}" -H "Authorization: Bearer ${SPLUNK_ACS_TOKEN}" -w '\n%{http_code}')
  if [[ -n "${data}" ]]; then args+=(-H 'Content-Type: application/json' -d "${data}"); fi
  curl "${args[@]}" "${url}"
}

# ── Command: index ───────────────────────────────────────────────────────────
cmd_index() {
  require_cmd curl; require_cmd jq
  [[ -n "${SPLUNK_STACK:-}" ]] || die "SPLUNK_STACK is required for index creation."
  [[ -n "${SPLUNK_ACS_TOKEN}" ]] || die "SPLUNK_ACS_TOKEN is required for index creation."

  step "Splunk Cloud Platform index: ${SPLUNK_INDEX} (stack: ${SPLUNK_STACK})"

  local resp code
  resp="$(acs_curl GET "/indexes/${SPLUNK_INDEX}")" || true
  code="$(tail -n1 <<<"${resp}")"
  if [[ "${code}" == "200" ]]; then
    ok "Index '${SPLUNK_INDEX}' already exists."
    return 0
  elif [[ "${code}" == "401" || "${code}" == "403" ]]; then
    die "ACS auth failed (HTTP ${code}). Check SPLUNK_ACS_TOKEN and that ACS is enabled on this stack."
  fi

  local body
  body="$(jq -nc \
    --arg name "${SPLUNK_INDEX}" \
    --argjson days "${SPLUNK_INDEX_SEARCHABLE_DAYS}" \
    --argjson maxmb "${SPLUNK_INDEX_MAX_SIZE_MB}" \
    '{name:$name, datatype:"event", searchableDays:$days, maxDataSizeMB:$maxmb}')"

  info "Creating index via ACS..."
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '    %s[dry-run]%s POST %s/indexes %s\n' "${c_yellow}" "${c_reset}" "$(acs_base)" "${body}"
    return 0
  fi
  resp="$(acs_curl POST "/indexes" "${body}")" || true
  code="$(tail -n1 <<<"${resp}")"
  case "${code}" in
    200|201|202)
      ok "Index create accepted (HTTP ${code}). ACS provisions asynchronously."
      info "Waiting for index to become available..."
      for _ in $(seq 1 30); do
        resp="$(acs_curl GET "/indexes/${SPLUNK_INDEX}")" || true
        [[ "$(tail -n1 <<<"${resp}")" == "200" ]] && { ok "Index '${SPLUNK_INDEX}' is ready."; return 0; }
        sleep 10
      done
      warn "Index not confirmed ready yet; it may still be provisioning. Re-run 'status' later."
      ;;
    409) ok "Index '${SPLUNK_INDEX}' already exists (HTTP 409)." ;;
    *)   die "Index creation failed (HTTP ${code}):"$'\n'"$(sed '$d' <<<"${resp}")" ;;
  esac
}

# ── Command: hec ─────────────────────────────────────────────────────────────
cmd_hec() {
  require_cmd curl; require_cmd jq
  [[ -n "${SPLUNK_STACK:-}" ]] || die "SPLUNK_STACK is required for HEC token management."
  [[ -n "${SPLUNK_ACS_TOKEN}" ]] || die "SPLUNK_ACS_TOKEN is required for HEC token management."

  step "Splunk Cloud Platform HEC token: ${SPLUNK_HEC_NAME} -> index ${SPLUNK_INDEX}"

  local resp code token
  resp="$(acs_curl GET "/hec-tokens/${SPLUNK_HEC_NAME}")" || true
  code="$(tail -n1 <<<"${resp}")"
  if [[ "${code}" == "200" ]]; then
    token="$(sed '$d' <<<"${resp}" | jq -r '.token // .http_event_collector_token.token // .hectoken.token // empty')"
    if [[ -n "${token}" ]]; then
      ok "HEC token '${SPLUNK_HEC_NAME}' already exists."
      HEC_TOKEN_RESOLVED="${token}"
      info "HEC token: $(mask "${token}")"
      return 0
    fi
    warn "HEC token exists but value not returned by ACS; set SPLUNK_HEC_TOKEN manually."
    return 0
  fi

  local body
  body="$(jq -nc \
    --arg name "${SPLUNK_HEC_NAME}" \
    --arg idx "${SPLUNK_INDEX}" \
    '{name:$name, allowedIndexes:[$idx], defaultIndex:$idx, disabled:false}')"

  info "Creating HEC token via ACS..."
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '    %s[dry-run]%s POST %s/hec-tokens %s\n' "${c_yellow}" "${c_reset}" "$(acs_base)" "${body}"
    return 0
  fi
  resp="$(acs_curl POST "/hec-tokens" "${body}")" || true
  code="$(tail -n1 <<<"${resp}")"
  case "${code}" in
    200|201|202)
      token="$(sed '$d' <<<"${resp}" | jq -r '.token // .http_event_collector_token.token // .hectoken.token // empty')"
      [[ -n "${token}" ]] || die "HEC token created but value could not be parsed. Raw:"$'\n'"$(sed '$d' <<<"${resp}")"
      HEC_TOKEN_RESOLVED="${token}"
      ok "HEC token created."
      info "HEC token: $(mask "${token}")  (store it in SPLUNK_HEC_TOKEN / 1Password)"
      ;;
    *) die "HEC token creation failed (HTTP ${code}):"$'\n'"$(sed '$d' <<<"${resp}")" ;;
  esac
}

# Ensure we have a usable HEC token in HEC_TOKEN_RESOLVED.
resolve_hec_token() {
  HEC_TOKEN_RESOLVED="${SPLUNK_HEC_TOKEN}"
  [[ -n "${HEC_TOKEN_RESOLVED}" ]] && return 0
  if [[ -n "${SPLUNK_STACK:-}" && -n "${SPLUNK_ACS_TOKEN}" ]]; then
    info "SPLUNK_HEC_TOKEN empty; resolving via ACS..."
    cmd_hec
  fi
  [[ -n "${HEC_TOKEN_RESOLVED:-}" ]] || die "Platform logs require a HEC token. Run 'hec' or set SPLUNK_HEC_TOKEN."
}

# ── Command: enable ──────────────────────────────────────────────────────────
ensure_helm_repo() {
  if ! helm repo list 2>/dev/null | grep -q "^${HELM_REPO_NAME}[[:space:]]"; then
    run helm repo add "${HELM_REPO_NAME}" "${HELM_REPO_URL}"
  fi
  run helm repo update "${HELM_REPO_NAME}" >/dev/null
}

cmd_enable() {
  require_cmd kubectl; require_cmd helm
  [[ -n "${SPLUNK_ACCESS_TOKEN}" ]] || die "SPLUNK_ACCESS_TOKEN (O11y) is required to (re)create the collector secret."
  helm status "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}" >/dev/null 2>&1 \
    || die "Collector release '${HELM_RELEASE}' not found in ${OTEL_NAMESPACE}. Run ./scripts/splunk-instrumentation.sh all first."

  resolve_hec_token
  local hec_url; hec_url="$(derive_hec_url)"

  step "Enabling Splunk Cloud Platform log export (index ${SPLUNK_INDEX})"
  info "HEC endpoint: ${hec_url}"

  # Update the chart secret to carry BOTH the O11y access token and the HEC token
  # (the chart reads splunk_platform_hec_token from this secret when secret.create=false).
  local sargs=(create secret generic "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}"
    --from-literal=splunk_observability_access_token="${SPLUNK_ACCESS_TOKEN}"
    --from-literal=splunk_platform_hec_token="${HEC_TOKEN_RESOLVED}")
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '    %s[dry-run]%s kubectl %s --dry-run=client -o yaml | kubectl apply -f -\n' \
      "${c_yellow}" "${c_reset}" "${sargs[*]//${SPLUNK_ACCESS_TOKEN}/$(mask "${SPLUNK_ACCESS_TOKEN}")}"
  else
    kubectl "${sargs[@]}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    ok "Secret '${HELM_RELEASE}' updated with the HEC token."
  fi

  ensure_helm_repo

  # `helm upgrade --reuse-values` re-applies the instrumentation CR's spec.java.env,
  # which the Operator also owns (server-side-apply field-manager conflict) and would
  # fail the upgrade. Delete the CR first so Helm recreates it cleanly; already-injected
  # app pods keep running until their next rollout.
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    run kubectl delete instrumentation "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}" --ignore-not-found
  fi

  # --reuse-values keeps all the O11y settings from splunk-instrumentation.sh; we only
  # add the Splunk Cloud Platform log-export leg here (this script stays decoupled).
  run helm upgrade --install "${HELM_RELEASE}" "${HELM_CHART}" \
    --namespace "${OTEL_NAMESPACE}" --reuse-values \
    --set "secret.create=false" \
    --set "secret.name=${HELM_RELEASE}" \
    --set "splunkPlatform.endpoint=${hec_url}" \
    --set "splunkPlatform.index=${SPLUNK_INDEX}" \
    --set "splunkPlatform.logsEnabled=true" \
    --set "splunkPlatform.metricsEnabled=false" \
    --set "splunkPlatform.tracesEnabled=false" \
    --wait --timeout 8m
  ok "Platform-logs export enabled on '${HELM_RELEASE}'."
  info "Next: in O11y, configure Log Observer Connect to federate stack '${SPLUNK_STACK}' and query index '${SPLUNK_INDEX}'."
}

# ── Command: disable ─────────────────────────────────────────────────────────
cmd_disable() {
  require_cmd kubectl; require_cmd helm
  helm status "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}" >/dev/null 2>&1 \
    || die "Collector release '${HELM_RELEASE}' not found in ${OTEL_NAMESPACE}."

  step "Disabling Splunk Cloud Platform log export"
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    run kubectl delete instrumentation "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}" --ignore-not-found
  fi
  run helm upgrade --install "${HELM_RELEASE}" "${HELM_CHART}" \
    --namespace "${OTEL_NAMESPACE}" --reuse-values \
    --set "splunkPlatform.logsEnabled=false" \
    --wait --timeout 8m
  ok "Platform-logs export disabled. O11y traces/metrics/profiling are untouched."
}

# ── Command: verify ──────────────────────────────────────────────────────────
# Confirms each log export leg is actually shipping records, straight from the
# collector agent's own telemetry. If platform_logs is sending but O11y "Related
# Logs" is still empty, the gap is the LOC connection (read side), not the
# collector (send side).
cmd_verify() {
  require_cmd kubectl
  step "Verifying log export legs (collector agent counters)"

  local ns="${OTEL_NAMESPACE}" pod
  pod="$(kubectl get pod -n "${ns}" -l component=otel-collector-agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -z "${pod}" ]]; then
    ns="$(kubectl get pod -A -l component=otel-collector-agent -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)"
    pod="$(kubectl get pod -A -l component=otel-collector-agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  fi
  [[ -n "${pod}" ]] || die "No collector agent pod found (label component=otel-collector-agent)."
  info "agent pod: ${ns}/${pod}"

  # The agent exposes its own telemetry on :8889 (curl/wget are absent from the
  # container image), so port-forward and scrape from the host.
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '    %s[dry-run]%s kubectl port-forward -n %s pod/%s 8889:8889 then curl :8889/metrics\n' \
      "${c_yellow}" "${c_reset}" "${ns}" "${pod}"
    return 0
  fi
  require_cmd curl
  kubectl port-forward -n "${ns}" "pod/${pod}" 8889:8889 >/dev/null 2>&1 &
  local pf_pid=$!
  # Self-clearing RETURN trap: guard pf_pid under `set -u` and reset the trap so
  # it does not re-fire (unbound) when later functions return.
  trap 'kill "${pf_pid:-}" 2>/dev/null || true; trap - RETURN' RETURN

  local i metrics=""
  for i in $(seq 1 20); do
    metrics="$(curl -sf "http://localhost:8889/metrics" 2>/dev/null || true)"
    [[ -n "${metrics}" ]] && break
    sleep 0.5
  done
  [[ -n "${metrics}" ]] || die "Could not scrape collector metrics on :8889."

  # Report sent/failed per log exporter (summed across label series). The trailing
  # `|| true` matters: when a series is absent, grep returns 1 and, under
  # `set -o pipefail`, the assignment would trip `set -e` and abort the script.
  local exp sent failed
  for exp in "splunk_hec/o11y" "splunk_hec/platform_logs" "otlp_http/secureapp"; do
    sent="$(grep -E "otelcol_exporter_sent_log_records\{.*exporter=\"${exp}\"" <<<"${metrics}" | awk '{s+=$NF} END{print s+0}' || true)"
    failed="$(grep -E "otelcol_exporter_send_failed_log_records\{.*exporter=\"${exp}\"" <<<"${metrics}" | awk '{s+=$NF} END{print s+0}' || true)"
    sent="${sent:-0}"; failed="${failed:-0}"
    if [[ "${sent%.*}" -le 0 ]]; then
      warn "${exp}: sent=${sent} failed=${failed}  (no records yet — generate traffic?)"
    elif [[ "${failed%.*}" -gt 0 ]]; then
      warn "${exp}: sent=${sent} failed=${failed}  (export errors — check token/endpoint)"
    else
      ok "${exp}: sent=${sent} failed=${failed}"
    fi
  done

  step "Splunk Cloud spot-check (run these in Splunk Web on the current stack)"
  info "Trace-correlated app logs:  index=${SPLUNK_INDEX} trace_id=*"
  info "By service:                 index=${SPLUNK_INDEX} service.name=\"${ENVIRONMENT}-operations-service\""
  info "If those return rows but O11y 'Related Logs' is still empty, the gap is the"
  info "Log Observer Connect connection (service account / index allowlist / stack URL),"
  info "not the collector send path."
}

# ── Command: status ──────────────────────────────────────────────────────────
cmd_status() {
  require_cmd kubectl
  step "Splunk Cloud logs status"
  info "Stack:        ${SPLUNK_STACK:-<unset>}"
  info "Index:        ${SPLUNK_INDEX}"
  info "HEC name:     ${SPLUNK_HEC_NAME}"
  info "Collector ns: ${OTEL_NAMESPACE}   release: ${HELM_RELEASE}"

  if [[ -n "${SPLUNK_STACK:-}" && -n "${SPLUNK_ACS_TOKEN}" ]] && command -v curl >/dev/null; then
    local code; code="$(acs_curl GET "/indexes/${SPLUNK_INDEX}" 2>/dev/null | tail -n1 || true)"
    [[ "${code}" == "200" ]] && ok "Index '${SPLUNK_INDEX}' exists." || warn "Index '${SPLUNK_INDEX}' not found (HTTP ${code:-?})."
  fi

  if helm status "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}" >/dev/null 2>&1; then
    local le
    le="$(helm get values "${HELM_RELEASE}" -n "${OTEL_NAMESPACE}" -o json 2>/dev/null \
      | jq -r '.splunkPlatform.logsEnabled // "false"' 2>/dev/null || echo "unknown")"
    [[ "${le}" == "true" ]] && ok "Platform-logs export is ENABLED on '${HELM_RELEASE}'." \
      || warn "Platform-logs export is off on '${HELM_RELEASE}' (splunkPlatform.logsEnabled=${le})."
  else
    warn "Collector release '${HELM_RELEASE}' not installed. Run ./scripts/splunk-instrumentation.sh all first."
  fi
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
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

  case "${cmd}" in
    help|-h|--help) usage; exit 0 ;;
  esac

  load_env

  case "${cmd}" in
    index)   cmd_index ;;
    hec)     cmd_hec ;;
    enable)  cmd_enable ;;
    verify)  cmd_verify ;;
    disable) cmd_disable ;;
    status)  cmd_status ;;
    all)
      # The log forwarder only needs a HEC token + endpoint. ACS (index/hec) is
      # only used to auto-provision those, so skip it when a HEC token is supplied
      # (SPLUNK_ACS_TOKEN is then not required).
      if [[ -n "${SPLUNK_HEC_TOKEN}" ]]; then
        info "SPLUNK_HEC_TOKEN set — skipping ACS index/HEC creation (SPLUNK_ACS_TOKEN not required)."
      else
        cmd_index
        cmd_hec
      fi
      cmd_enable
      cmd_verify
      step "Done — Splunk Cloud logs / Log Observer Connect"
      info "Java-agent logs -> Splunk Cloud Platform index '${SPLUNK_INDEX}' (HEC ${SPLUNK_HEC_NAME})."
      info "Next: in O11y, configure Log Observer Connect to federate stack '${SPLUNK_STACK:-<stack>}'."
      ;;
    *) usage; die "Unknown command: ${cmd}" ;;
  esac
}

main "$@"
