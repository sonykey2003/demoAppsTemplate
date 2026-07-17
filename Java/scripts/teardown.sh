#!/usr/bin/env bash
# scripts/teardown.sh — Tear down the Port Ops Demo from Kubernetes.
# Usage: ./scripts/teardown.sh [--help]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OVERLAY="${ROOT}/k8s/overlays/demo"
NAMESPACE="port-ops-demo"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Remove all Port Ops Demo resources from the cluster.

Actions:
  1. kubectl delete -k k8s/overlays/demo

Options:
  --help    Show this help message and exit

WARNING: This will delete the port-ops-demo namespace and all its resources,
         including persistent volumes. Data will be lost.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $arg"; usage; exit 1 ;;
  esac
done

echo "==> Deleting kustomize overlay resources..."
kubectl delete -k "${OVERLAY}" --ignore-not-found=true

echo ""
echo "✓ Teardown complete. Namespace '${NAMESPACE}' and all resources removed."
