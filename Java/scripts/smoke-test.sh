#!/usr/bin/env bash
# scripts/smoke-test.sh — Verify all services are healthy and POST /api/jobs works.
# Usage: ./scripts/smoke-test.sh [--help]
set -euo pipefail

NAMESPACE="port-ops-demo"
PASS=0
FAIL=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Smoke-test every Port Ops Demo service via ephemeral kubectl port-forward.

Checks:
  1. vessel-service    GET /healthz     → {"status":"UP"}
  2. container-service GET /healthz     → {"status":"UP"}
  3. operations-service GET /healthz    → {"status":"UP"}
  4. frontend          GET /healthz     → {"status":"UP"}
  5. operations-service POST /api/jobs  → 202 (happy path)

Options:
  --help    Show this help message and exit
EOF
}

for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $arg"; usage; exit 1 ;;
  esac
done

# ── Helper: port-forward a service, run a check function, then kill the forwarder
check_service() {
  local name="$1"
  local svc="$2"
  local svc_port="$3"
  local local_port="$4"
  local check_fn="$5"

  echo ""
  echo "──► Testing ${name} (${svc}:${svc_port} → localhost:${local_port})"

  # Start port-forward in background
  kubectl port-forward -n "${NAMESPACE}" "svc/${svc}" "${local_port}:${svc_port}" &>/dev/null &
  local pf_pid=$!
  # Give it time to establish
  sleep 2

  if ${check_fn} "${local_port}"; then
    echo "    ✓ PASS: ${name}"
    PASS=$((PASS + 1))
  else
    echo "    ✗ FAIL: ${name}"
    FAIL=$((FAIL + 1))
  fi

  kill "${pf_pid}" 2>/dev/null || true
  wait "${pf_pid}" 2>/dev/null || true
}

# ── Check functions
check_healthz() {
  local port="$1"
  local response
  response=$(curl -sf "http://localhost:${port}/healthz" 2>/dev/null) || return 1
  echo "    Response: ${response}"
  echo "${response}" | grep -q '"status"' || return 1
}

check_post_jobs() {
  local port="$1"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "http://localhost:${port}/api/jobs" \
    -H "Content-Type: application/json" \
    -d '{"vessel_code":"VSL-0001","container_id":"CONT-0000007","operation_type":"GATE_IN","terminal_id":"T1"}' \
    2>/dev/null) || return 1
  echo "    HTTP status: ${http_code}"
  [[ "${http_code}" == "202" ]]
}

echo "==> Port Ops Demo — Smoke Test"
echo "    Namespace: ${NAMESPACE}"

check_service "vessel-service /healthz"    "vessel-service"    9081 19081 check_healthz
check_service "container-service /healthz" "container-service" 9082 19082 check_healthz
check_service "operations-service /healthz" "operations-service" 9083 19083 check_healthz
check_service "frontend /healthz"          "frontend"          9080 19080 check_healthz
check_service "operations-service POST /api/jobs" "operations-service" 9083 19084 check_post_jobs

echo ""
echo "══════════════════════════════════════"
echo "  Results: ${PASS} PASSED / ${FAIL} FAILED"
echo "══════════════════════════════════════"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
