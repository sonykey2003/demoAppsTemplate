#!/usr/bin/env bash
# scripts/deploy.sh — Deploy Port Ops Demo to Kubernetes via kustomize.
# Usage: ./scripts/deploy.sh [--help]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OVERLAY="${ROOT}/k8s/overlays/demo"
NAMESPACE="port-ops-demo"

DEPLOYMENTS=(
  postgres
  redis
  vessel-service
  container-service
  operations-service
  frontend
)

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Deploy the Port Ops Demo to the current kubectl context using kustomize.

Prerequisites:
  - kubectl configured with a target cluster
  - Secrets created (see README.md "Create Secrets" section)
  - Images built and loaded (scripts/build-images.sh + scripts/load-images-kind.sh)

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

echo "==> Applying kustomize overlay: ${OVERLAY}"
kubectl apply -k "${OVERLAY}"

echo ""
echo "==> Waiting for Deployments to roll out in namespace '${NAMESPACE}'..."
for dep in "${DEPLOYMENTS[@]}"; do
  echo "──► kubectl rollout status deployment/${dep} -n ${NAMESPACE}"
  kubectl rollout status deployment/"${dep}" -n "${NAMESPACE}" --timeout=120s
done

echo ""
echo "✓ Deployment complete."
echo ""
echo "Access the UI:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/frontend 9080:9080"
echo "  Then open: http://localhost:9080"
echo ""
echo "Or via NodePort (if your cluster exposes node IPs):"
echo "  http://<node-ip>:31080"
