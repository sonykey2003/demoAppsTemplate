#!/usr/bin/env bash
# scripts/build-images.sh — Build all Port Ops Demo Docker images locally.
# Usage: ./scripts/build-images.sh [--include-vuln-demo]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_PREFIX="localhost/port-ops-demo"
VERSION="0.1.0"
INCLUDE_VULN_DEMO="false"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build all 4 Port Ops Demo Docker images.

Options:
  --include-vuln-demo  Also build operations-service:${VERSION}-vuln-demo
  --help               Show this help message and exit

Images built:
  ${IMAGE_PREFIX}/vessel-service:${VERSION}
  ${IMAGE_PREFIX}/container-service:${VERSION}
  ${IMAGE_PREFIX}/operations-service:${VERSION}
  ${IMAGE_PREFIX}/frontend:${VERSION}

Vulnerability demo image:
  ${IMAGE_PREFIX}/operations-service:${VERSION}-vuln-demo
EOF
}

for arg in "$@"; do
  case "$arg" in
    --include-vuln-demo) INCLUDE_VULN_DEMO="true" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $arg"; usage; exit 1 ;;
  esac
done

echo "==> Building Port Ops Demo images (prefix: ${IMAGE_PREFIX}, version: ${VERSION})"

# Backend services (source dir → image tag)
for svc in vessel-service container-service operations-service; do
  echo ""
  echo "──► Building ${IMAGE_PREFIX}/${svc}:${VERSION}"
  docker build \
    --tag "${IMAGE_PREFIX}/${svc}:${VERSION}" \
    "${ROOT}/services/${svc}"
done

if [ "${INCLUDE_VULN_DEMO}" = "true" ]; then
  echo ""
  echo "──► Building ${IMAGE_PREFIX}/operations-service:${VERSION}-vuln-demo"
  docker build \
    --build-arg MAVEN_PROFILES=vuln-demo \
    --tag "${IMAGE_PREFIX}/operations-service:${VERSION}-vuln-demo" \
    "${ROOT}/services/operations-service"
fi

# Frontend
echo ""
echo "──► Building ${IMAGE_PREFIX}/frontend:${VERSION}"
docker build \
  --tag "${IMAGE_PREFIX}/frontend:${VERSION}" \
  "${ROOT}/frontend"

echo ""
echo "✓ All images built successfully."
docker images --filter "reference=${IMAGE_PREFIX}/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
