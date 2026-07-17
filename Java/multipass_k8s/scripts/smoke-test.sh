#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# smoke-test.sh — Quick health check against the multipass k3s deployment.
#
# Verifies node/pod spread and hits the frontend health endpoint via NodePort.
#
# Usage: ./scripts/smoke-test.sh
# ─────────────────────────────────────────────────────────────────────────────
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_cmd kubectl
require_cmd curl

[[ -f "${KUBECONFIG_FILE}" ]] || die "No kubeconfig at ${KUBECONFIG_FILE}. Run scripts/up.sh first."
export KUBECONFIG="${KUBECONFIG_FILE}"

log "Nodes"
kubectl get nodes -o wide

echo ""
log "Replica spread per service (should be 1 pod per node = 4 nodes)"
for svc in "${APP_IMAGES[@]}"; do
  count_by_node="$(kubectl -n "${NAMESPACE}" get pods \
    -l "app.kubernetes.io/component=${svc}" \
    -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null \
    | sort | uniq -c | awk '{printf "%s=%s ", $2, $1}')"
  printf '  %-20s %s\n' "${svc}" "${count_by_node:-<none>}"
done

echo ""
SERVER_IP="$(vm_ipv4 "${SERVER_VM}" || true)"
if [[ -n "${SERVER_IP}" ]]; then
  log "Frontend health via NodePort http://${SERVER_IP}:31080/healthz"
  if curl -fsS --max-time 10 "http://${SERVER_IP}:31080/healthz" >/dev/null; then
    echo "  ✓ frontend healthy"
  else
    warn "frontend /healthz did not respond (pods may still be starting)"
  fi
fi
