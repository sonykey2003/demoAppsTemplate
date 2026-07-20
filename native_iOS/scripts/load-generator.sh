#!/usr/bin/env bash
# scripts/load-generator.sh — Generate synthetic traffic against the SEA Bank gateway
# to produce APM/RUM demo telemetry.
#
# Scenarios:
#   login     — repeated POST /api/login
#   balance   — repeated GET  /api/dashboard (balance + cache spans)
#   transfer  — repeated POST /api/transfers (fan-out + async settle)
#   latency   — dashboard calls with an injected per-request latency header
#   fail      — dashboard calls with an injected per-request error rate
#   mixed     — interleave login + balance + transfer (default)
set -euo pipefail

SCENARIO="mixed"
RPS=2
DURATION=300      # seconds; 0 = forever
NAMESPACE="sea-bank-demo"
LOCAL_PORT="28081"
BASE_URL="${BASE_URL:-}"
FAULT_LATENCY_MS="1500"
FAULT_ERROR_RATE="0.5"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --scenario <name>   login | balance | transfer | latency | fail | mixed  (default: ${SCENARIO})
  --rps <n>           requests per second            (default: ${RPS})
  --duration <s>      run for N seconds, 0=forever   (default: ${DURATION})
  --port <n>          local port for port-forward    (default: ${LOCAL_PORT})
  --help              Show this help.

Set BASE_URL to skip the auto port-forward (e.g. BASE_URL=http://localhost:8080).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) SCENARIO="$2"; shift 2 ;;
    --rps)      RPS="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --port)     LOCAL_PORT="$2"; shift 2 ;;
    --help|-h)  usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

case "${SCENARIO}" in login|balance|transfer|latency|fail|mixed) ;; *) echo "Unknown scenario '${SCENARIO}'"; usage; exit 1 ;; esac

PF_PID=""
cleanup() { [[ -n "${PF_PID}" ]] && kill "${PF_PID}" 2>/dev/null || true; }
trap cleanup EXIT

if [[ -z "${BASE_URL}" ]]; then
  kubectl -n "${NAMESPACE}" port-forward svc/api-gateway "${LOCAL_PORT}:8080" >/dev/null 2>&1 &
  PF_PID=$!
  BASE_URL="http://localhost:${LOCAL_PORT}"
fi

for _ in $(seq 1 30); do curl -sf "${BASE_URL}/healthz" >/dev/null 2>&1 && break; sleep 0.5; done
curl -sf "${BASE_URL}/healthz" >/dev/null 2>&1 || { echo "gateway not reachable at ${BASE_URL}"; exit 1; }

login() {
  curl -s -X POST "${BASE_URL}/api/login" -H 'content-type: application/json' \
    -d '{"username":"demo","password":"demo"}' \
    | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{process.stdout.write(JSON.parse(d).token||"")}catch{}})'
}

TOKEN="$(login)"
[[ -n "${TOKEN}" ]] || { echo "initial login failed"; exit 1; }

echo "==> Scenario '${SCENARIO}' @ ${RPS} rps for ${DURATION}s against ${BASE_URL}"
SLEEP_INTERVAL="$(awk "BEGIN {printf \"%.3f\", 1/${RPS}}")"
END_TS=$(( DURATION > 0 ? $(date +%s) + DURATION : 0 ))
FROM=(ACC-1001 ACC-1002); TO=(ACC-1002 ACC-1001)
i=0

hit_dashboard() { curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' "$@" "${BASE_URL}/api/dashboard" -H "authorization: Bearer ${TOKEN}"; }

while :; do
  case "${SCENARIO}" in
    login)    curl -s -o /dev/null -w 'login %{http_code}\n' -X POST "${BASE_URL}/api/login" -H 'content-type: application/json' -d '{"username":"demo","password":"demo"}' ;;
    balance)  echo -n "balance "; hit_dashboard ;;
    transfer) f="${FROM[$((i % 2))]}"; t="${TO[$((i % 2))]}"; curl -s -o /dev/null -w 'transfer %{http_code}\n' -X POST "${BASE_URL}/api/transfers" -H "authorization: Bearer ${TOKEN}" -H 'content-type: application/json' -d "{\"fromAccountId\":\"${f}\",\"toAccountId\":\"${t}\",\"amount\":10}" ;;
    latency)  echo -n "latency "; hit_dashboard -H "x-fault-latency-ms: ${FAULT_LATENCY_MS}" ;;
    fail)     echo -n "fail "; hit_dashboard -H "x-fault-error-rate: ${FAULT_ERROR_RATE}" ;;
    mixed)
      case $(( i % 3 )) in
        0) curl -s -o /dev/null -w 'login %{http_code}\n' -X POST "${BASE_URL}/api/login" -H 'content-type: application/json' -d '{"username":"demo","password":"demo"}' ;;
        1) echo -n "balance "; hit_dashboard ;;
        2) curl -s -o /dev/null -w 'transfer %{http_code}\n' -X POST "${BASE_URL}/api/transfers" -H "authorization: Bearer ${TOKEN}" -H 'content-type: application/json' -d '{"fromAccountId":"ACC-1001","toAccountId":"ACC-1002","amount":10}' ;;
      esac ;;
  esac
  i=$(( i + 1 ))
  [[ "${END_TS}" -ne 0 && "$(date +%s)" -ge "${END_TS}" ]] && break
  sleep "${SLEEP_INTERVAL}"
done

echo "==> Done (${i} requests)."
