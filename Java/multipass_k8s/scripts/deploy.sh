#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy.sh — Deploy Port Ops Demo onto the multipass k3s cluster.
#
# Creates the postgres secret (once), applies the multipass kustomize overlay
# (4 replicas per service, spread one-per-VM), and waits for rollout.
#
# Requires the cluster to be up (scripts/up.sh) and images loaded
# (scripts/load-images.sh). Uses the kubeconfig written by up.sh.
#
# Usage: ./scripts/deploy.sh
# ─────────────────────────────────────────────────────────────────────────────
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_cmd kubectl
require_cmd openssl

[[ -f "${KUBECONFIG_FILE}" ]] || die "No kubeconfig at ${KUBECONFIG_FILE}. Run scripts/up.sh first."
export KUBECONFIG="${KUBECONFIG_FILE}"

OVERLAY="${MP_ROOT}/k8s"

DEPLOYMENTS=(
  postgres
  redis
  vessel-service
  container-service
  operations-service
  frontend
)

# ── 1. Namespace ─────────────────────────────────────────────────────────────
log "Ensuring namespace ${NAMESPACE}"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# ── 2. Postgres secret (generate + persist once) ─────────────────────────────
if kubectl -n "${NAMESPACE}" get secret port-ops-postgres >/dev/null 2>&1; then
  log "Secret port-ops-postgres already exists — keeping it."
else
  if [[ -f "${PG_PASSWORD_FILE}" ]]; then
    PG_PASSWORD="$(cat "${PG_PASSWORD_FILE}")"
  else
    PG_PASSWORD="$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9')"
    printf '%s' "${PG_PASSWORD}" > "${PG_PASSWORD_FILE}"
    chmod 600 "${PG_PASSWORD_FILE}"
  fi
  log "Creating secret port-ops-postgres (password saved to ${PG_PASSWORD_FILE})"
  kubectl -n "${NAMESPACE}" create secret generic port-ops-postgres \
    --from-literal=username=portops \
    --from-literal=password="${PG_PASSWORD}"
fi

# ── 3. Apply the overlay ─────────────────────────────────────────────────────
log "Applying multipass overlay: ${OVERLAY}"
kubectl apply -k "${OVERLAY}"

# ── 4. Wait for rollout ──────────────────────────────────────────────────────
echo ""
log "Waiting for rollouts in ${NAMESPACE}"
for dep in "${DEPLOYMENTS[@]}"; do
  echo "──► rollout status deployment/${dep}"
  kubectl -n "${NAMESPACE}" rollout status "deployment/${dep}" --timeout=180s
done

# ── 5. Show the even spread ──────────────────────────────────────────────────
echo ""
log "Pod distribution across nodes:"
kubectl -n "${NAMESPACE}" get pods -o wide \
  --sort-by='.spec.nodeName' \
  -o=custom-columns='POD:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase'

SERVER_IP="$(vm_ipv4 "${SERVER_VM}" || true)"
echo ""
log "Access the UI (NodePort 31080 on any node):"
echo "    http://${SERVER_IP:-<node-ip>}:31080"
echo "  or port-forward:"
echo "    KUBECONFIG=${KUBECONFIG_FILE} kubectl -n ${NAMESPACE} port-forward svc/frontend 9080:9080"
