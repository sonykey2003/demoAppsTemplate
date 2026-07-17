#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# lib.sh — shared configuration + helpers for the multipass / k3s deploy path.
# Sourced by up.sh, load-images.sh, deploy.sh, down.sh, smoke-test.sh.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# Resolve directories relative to this file (works no matter where it's called).
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MP_ROOT="$(cd "${LIB_DIR}/.." && pwd)"          # Java/multipass_k8s
PROJECT_ROOT="$(cd "${MP_ROOT}/.." && pwd)"     # Java

# ── Cluster topology ─────────────────────────────────────────────────────────
SERVER_VM="port-k3s-1"
AGENT_VMS=(port-k3s-2 port-k3s-3 port-k3s-4)
ALL_VMS=("${SERVER_VM}" "${AGENT_VMS[@]}")

# ── VM sizing (per node) ─────────────────────────────────────────────────────
VM_CPUS="2"
VM_MEM="4G"
VM_DISK="20G"
UBUNTU_IMAGE="24.04"

# ── App / image config (must match scripts/build-images.sh) ──────────────────
IMAGE_PREFIX="localhost/port-ops-demo"
IMAGE_VERSION="0.1.0"
APP_IMAGES=(frontend vessel-service container-service operations-service)
NAMESPACE="port-ops-demo"

# ── Files written at launch (git-ignored) ────────────────────────────────────
RENDERED_DIR="${MP_ROOT}/.rendered"
KUBECONFIG_FILE="${MP_ROOT}/kubeconfig"
TOKEN_FILE="${MP_ROOT}/.k3s-token"
PG_PASSWORD_FILE="${MP_ROOT}/.postgres-password"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found in PATH."
}

# Return the IPv4 address of a multipass VM (first non-loopback address).
vm_ipv4() {
  multipass info "$1" --format json 2>/dev/null \
    | grep -Eo '"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' \
    | tr -d '"' \
    | grep -v '^127\.' \
    | head -n1
}

# True if a multipass VM already exists (any state).
vm_exists() {
  multipass info "$1" >/dev/null 2>&1
}
