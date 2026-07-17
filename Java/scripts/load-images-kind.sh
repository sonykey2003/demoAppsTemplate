#!/usr/bin/env bash
# scripts/load-images-kind.sh — Load locally-built images into a kind cluster.
# Usage: ./scripts/load-images-kind.sh [--cluster <name>] [--help]
set -euo pipefail

IMAGE_PREFIX="localhost/port-ops-demo"
VERSION="0.1.0"
KIND_CLUSTER="port-ops-demo"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Load Port Ops Demo images into a kind (or minikube) cluster.

Options:
  --cluster <name>   kind cluster name (default: ${KIND_CLUSTER})
  --help             Show this help message and exit

Minikube alternative (uncomment in script or run manually):
  eval \$(minikube docker-env)
  # then re-run scripts/build-images.sh to build directly into minikube's daemon
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster) KIND_CLUSTER="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

IMAGES=(
  "${IMAGE_PREFIX}/vessel-service:${VERSION}"
  "${IMAGE_PREFIX}/container-service:${VERSION}"
  "${IMAGE_PREFIX}/operations-service:${VERSION}"
  "${IMAGE_PREFIX}/frontend:${VERSION}"
)

echo "==> Loading images into kind cluster: ${KIND_CLUSTER}"

for image in "${IMAGES[@]}"; do
  echo "──► kind load docker-image ${image} --name ${KIND_CLUSTER}"
  kind load docker-image "${image}" --name "${KIND_CLUSTER}"
done

echo ""
echo "✓ All images loaded into kind cluster '${KIND_CLUSTER}'."

# ─────────────────────────────────────────────────────────────────────────────
# Minikube alternative:
#   eval $(minikube docker-env --profile port-ops-demo)
#   ./scripts/build-images.sh
# This builds images directly into minikube's Docker daemon — no load needed.
# ─────────────────────────────────────────────────────────────────────────────
