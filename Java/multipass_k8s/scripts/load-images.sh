#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# load-images.sh — Distribute the locally-built app images into every k3s node.
#
# k3s uses containerd (not docker), so host-built images must be imported into
# each node's containerd image store. This does:
#     docker save  →  multipass transfer  →  sudo k3s ctr images import
# for all 4 app images on all 4 VMs (every node runs one replica of each service).
#
# Prereqs: images built on the host first —
#     (cd Java && ./scripts/build-images.sh)
#
# Usage: ./scripts/load-images.sh
# ─────────────────────────────────────────────────────────────────────────────
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_cmd multipass
require_cmd docker

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

for svc in "${APP_IMAGES[@]}"; do
  img="${IMAGE_PREFIX}/${svc}:${IMAGE_VERSION}"
  tar="${TMP_DIR}/${svc}.tar"

  if ! docker image inspect "${img}" >/dev/null 2>&1; then
    die "Image not found: ${img}. Build it first: (cd ${PROJECT_ROOT} && ./scripts/build-images.sh)"
  fi

  log "Saving ${img}"
  docker save "${img}" -o "${tar}"

  for vm in "${ALL_VMS[@]}"; do
    vm_exists "${vm}" || { warn "${vm} not found — skipping."; continue; }
    log "→ importing ${svc} into ${vm}"
    multipass transfer "${tar}" "${vm}:/tmp/${svc}.tar"
    multipass exec "${vm}" -- sudo k3s ctr images import "/tmp/${svc}.tar"
    multipass exec "${vm}" -- rm -f "/tmp/${svc}.tar"
  done
done

log "All app images imported into: ${ALL_VMS[*]}"
