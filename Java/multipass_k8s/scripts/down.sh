#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# down.sh — Tear down the multipass k3s cluster.
#
# Deletes and purges the 4 VMs. By default the generated token / kubeconfig /
# postgres-password files are kept; pass --clean to remove them too.
#
# Usage: ./scripts/down.sh [--clean]
# ─────────────────────────────────────────────────────────────────────────────
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_cmd multipass

CLEAN="false"
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN="true" ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown option: $arg" ;;
  esac
done

for vm in "${ALL_VMS[@]}"; do
  if vm_exists "${vm}"; then
    log "Deleting ${vm}"
    multipass delete "${vm}"
  fi
done

log "Purging deleted instances"
multipass purge

if [[ "${CLEAN}" == "true" ]]; then
  log "Removing generated files"
  rm -f "${KUBECONFIG_FILE}" "${TOKEN_FILE}" "${PG_PASSWORD_FILE}"
  rm -rf "${RENDERED_DIR}"
fi

log "Teardown complete."
