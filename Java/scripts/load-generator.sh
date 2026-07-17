#!/usr/bin/env bash
# scripts/load-generator.sh — Generate steady traffic against operations-service.
# Usage: ./scripts/load-generator.sh [--scenario <name>] [--rps <n>] [--help]
#
# Scenarios:
#   latency  — repeated GET /api/operations/slow?delay_ms=3000
#   fail     — repeated GET /api/operations/fail (always 500)
#   kpi      — repeated POST /api/jobs with GATE_IN (generates turnaround metrics)
#   mixed    — interleaved normal jobs + slow + fail calls (default)
set -euo pipefail

SCENARIO="mixed"
RPS=2
NAMESPACE="port-ops-demo"
LOCAL_PORT=29083
DURATION=300  # seconds to run (0 = run forever)

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Generate synthetic load against operations-service to produce demo telemetry.

Options:
  --scenario <name>   latency | fail | kpi | mixed  (default: ${SCENARIO})
  --rps <n>           requests per second           (default: ${RPS})
  --duration <s>      run for N seconds, 0=forever  (default: ${DURATION})
  --port <n>          local port for port-forward   (default: ${LOCAL_PORT})
  --help              Show this help message and exit

Examples:
  # Trigger latency spike scenario
  ./scripts/load-generator.sh --scenario latency --rps 4

  # Generate KPI metrics with normal job traffic
  ./scripts/load-generator.sh --scenario kpi --rps 2 --duration 120

  # Trigger error-rate scenario
  ./scripts/load-generator.sh --scenario fail --rps 5
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) SCENARIO="$2"; shift 2 ;;
    --rps)      RPS="$2";      shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --port)     LOCAL_PORT="$2"; shift 2 ;;
    --help|-h)  usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Validate scenario
case "$SCENARIO" in
  latency|fail|kpi|mixed) ;;
  *) echo "ERROR: Unknown scenario '${SCENARIO}'"; usage; exit 1 ;;
esac

BASE_URL="http://localhost:${LOCAL_PORT}"
SLEEP_INTERVAL=$(awk "BEGIN {printf \"%.3f\", 1/${RPS}}")

# Container IDs to cycle through for GATE_IN jobs (all seeded as INBOUND)
CONTAINERS=(
  CONT-0000007 CONT-0000008 CONT-0000009 CONT-0000010
  CONT-0000011 CONT-0000012 CONT-0000013 CONT-0000014
  CONT-0000015 CONT-0000016 CONT-0000017 CONT-0000018
)
VESSELS=(VSL-0001 VSL-0002 VSL-0003 VSL-0004 VSL-0005)
TERMINALS=(T1 T2 T3 T4)
OPS=(YARD_MOVE GATE_IN GATE_OUT BERTH_ALLOC)

container_idx=0
request_count=0
start_time=$(date +%s)

# ── Port-forward in background
echo "==> Starting port-forward: operations-service → localhost:${LOCAL_PORT}"
kubectl port-forward -n "${NAMESPACE}" svc/operations-service "${LOCAL_PORT}:9083" &>/dev/null &
PF_PID=$!
trap 'echo ""; echo "Stopping... (${request_count} requests sent)"; kill ${PF_PID} 2>/dev/null || true; wait ${PF_PID} 2>/dev/null || true' EXIT
sleep 2

echo "==> Load generator started  scenario=${SCENARIO}  rps=${RPS}"
echo "    Press Ctrl+C to stop."
echo ""

while true; do
  # Duration check
  if [[ ${DURATION} -gt 0 ]]; then
    elapsed=$(( $(date +%s) - start_time ))
    if [[ ${elapsed} -ge ${DURATION} ]]; then
      echo "Duration ${DURATION}s reached — stopping."
      break
    fi
  fi

  vessel="${VESSELS[$(( request_count % ${#VESSELS[@]} ))]}"
  container="${CONTAINERS[$(( container_idx % ${#CONTAINERS[@]} ))]}"
  terminal="${TERMINALS[$(( request_count % ${#TERMINALS[@]} ))]}"
  op="${OPS[$(( request_count % ${#OPS[@]} ))]}"

  case "$SCENARIO" in
    latency)
      # Scenario 1: Latency Spike — repeated slow calls
      delay_ms=$(( (RANDOM % 4000) + 1000 ))
      curl -sf "${BASE_URL}/api/operations/slow?delay_ms=${delay_ms}" -o /dev/null &
      printf "[%d] GET /api/operations/slow?delay_ms=%d\n" "$request_count" "$delay_ms"
      ;;

    fail)
      # Scenario 2: Dependency Failure — forced 500s
      http_code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/operations/fail" || echo 000)
      printf "[%d] GET /api/operations/fail → %s\n" "$request_count" "$http_code"
      ;;

    kpi)
      # Scenario 3: KPI — GATE_IN jobs to generate turnaround metrics
      http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${BASE_URL}/api/jobs" \
        -H "Content-Type: application/json" \
        -d "{\"vessel_code\":\"${vessel}\",\"container_id\":\"${container}\",\"operation_type\":\"GATE_IN\",\"terminal_id\":\"${terminal}\"}" || echo 000)
      printf "[%d] POST /api/jobs GATE_IN %s/%s → %s\n" "$request_count" "$vessel" "$container" "$http_code"
      container_idx=$(( container_idx + 1 ))
      ;;

    mixed)
      # Scenario 4: Mixed — normal jobs + occasional slow + occasional fail
      case $(( request_count % 5 )) in
        0)
          delay_ms=$(( (RANDOM % 3000) + 500 ))
          curl -sf "${BASE_URL}/api/operations/slow?delay_ms=${delay_ms}" -o /dev/null &
          printf "[%d] GET /api/operations/slow?delay_ms=%d\n" "$request_count" "$delay_ms"
          ;;
        4)
          http_code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/operations/fail" || echo 000)
          printf "[%d] GET /api/operations/fail → %s\n" "$request_count" "$http_code"
          ;;
        *)
          http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST "${BASE_URL}/api/jobs" \
            -H "Content-Type: application/json" \
            -d "{\"vessel_code\":\"${vessel}\",\"container_id\":\"${container}\",\"operation_type\":\"${op}\",\"terminal_id\":\"${terminal}\"}" || echo 000)
          printf "[%d] POST /api/jobs %s %s/%s → %s\n" "$request_count" "$op" "$vessel" "$container" "$http_code"
          container_idx=$(( container_idx + 1 ))
          ;;
      esac
      ;;
  esac

  request_count=$(( request_count + 1 ))
  sleep "${SLEEP_INTERVAL}"
done
