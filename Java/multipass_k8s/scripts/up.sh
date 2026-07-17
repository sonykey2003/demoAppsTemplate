#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# up.sh — Launch 4 multipass VMs and form a k3s cluster.
#
#   port-k3s-1  → k3s server (control-plane, schedulable)
#   port-k3s-2  ┐
#   port-k3s-3  ├ k3s agents (workers)
#   port-k3s-4  ┘
#
# Renders the cloud-init templates with a per-cluster token + the server IP,
# then writes a kubeconfig to ../kubeconfig pointing at the server VM.
#
# Usage: ./scripts/up.sh
# ─────────────────────────────────────────────────────────────────────────────
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_cmd multipass
require_cmd openssl
require_cmd sed

mkdir -p "${RENDERED_DIR}"

# ── 1. Per-cluster join token ────────────────────────────────────────────────
if [[ -f "${TOKEN_FILE}" ]]; then
  K3S_TOKEN="$(cat "${TOKEN_FILE}")"
  log "Reusing existing cluster token (${TOKEN_FILE})"
else
  K3S_TOKEN="$(openssl rand -hex 24)"
  printf '%s' "${K3S_TOKEN}" > "${TOKEN_FILE}"
  chmod 600 "${TOKEN_FILE}"
  log "Generated new cluster token → ${TOKEN_FILE}"
fi

# ── 2. Launch the server node ────────────────────────────────────────────────
if vm_exists "${SERVER_VM}"; then
  warn "${SERVER_VM} already exists — skipping launch."
else
  log "Rendering server cloud-init"
  sed "s|@@K3S_TOKEN@@|${K3S_TOKEN}|g" \
    "${MP_ROOT}/cloud-init/k3s-server.yaml" > "${RENDERED_DIR}/server.yaml"

  log "Launching ${SERVER_VM} (${VM_CPUS} CPU / ${VM_MEM} / ${VM_DISK})"
  multipass launch "${UBUNTU_IMAGE}" \
    --name "${SERVER_VM}" \
    --cpus "${VM_CPUS}" --memory "${VM_MEM}" --disk "${VM_DISK}" \
    --cloud-init "${RENDERED_DIR}/server.yaml"
fi

# ── 3. Discover the server IP ────────────────────────────────────────────────
log "Waiting for ${SERVER_VM} IPv4 address"
SERVER_IP=""
for _ in $(seq 1 30); do
  SERVER_IP="$(vm_ipv4 "${SERVER_VM}" || true)"
  [[ -n "${SERVER_IP}" ]] && break
  sleep 2
done
[[ -n "${SERVER_IP}" ]] || die "Could not determine ${SERVER_VM} IP address."
log "Server IP: ${SERVER_IP}"

# Wait until k3s on the server is actually answering.
log "Waiting for k3s API server on ${SERVER_VM}"
for _ in $(seq 1 60); do
  if multipass exec "${SERVER_VM}" -- k3s kubectl get nodes >/dev/null 2>&1; then
    break
  fi
  sleep 3
done

# ── 4. Launch agent nodes ────────────────────────────────────────────────────
log "Rendering agent cloud-init"
sed -e "s|@@K3S_TOKEN@@|${K3S_TOKEN}|g" \
    -e "s|@@K3S_URL@@|${SERVER_IP}|g" \
    "${MP_ROOT}/cloud-init/k3s-agent.yaml" > "${RENDERED_DIR}/agent.yaml"

for vm in "${AGENT_VMS[@]}"; do
  if vm_exists "${vm}"; then
    warn "${vm} already exists — skipping launch."
    continue
  fi
  log "Launching ${vm} (${VM_CPUS} CPU / ${VM_MEM} / ${VM_DISK})"
  multipass launch "${UBUNTU_IMAGE}" \
    --name "${vm}" \
    --cpus "${VM_CPUS}" --memory "${VM_MEM}" --disk "${VM_DISK}" \
    --cloud-init "${RENDERED_DIR}/agent.yaml"
done

# ── 5. Fetch kubeconfig, rewrite server address ──────────────────────────────
log "Fetching kubeconfig → ${KUBECONFIG_FILE}"
multipass exec "${SERVER_VM}" -- sudo cat /etc/rancher/k3s/k3s.yaml > "${KUBECONFIG_FILE}"
# macOS/BSD sed needs an explicit empty backup suffix after -i.
sed -i '' "s|https://127.0.0.1:6443|https://${SERVER_IP}:6443|g" "${KUBECONFIG_FILE}"
chmod 600 "${KUBECONFIG_FILE}"

# ── 6. Wait for all nodes Ready ──────────────────────────────────────────────
export KUBECONFIG="${KUBECONFIG_FILE}"
log "Waiting for all ${#ALL_VMS[@]} nodes to report Ready"
for _ in $(seq 1 60); do
  ready="$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || true)"
  [[ "${ready}" -ge "${#ALL_VMS[@]}" ]] && break
  sleep 3
done

echo ""
kubectl get nodes -o wide || true
echo ""
log "Cluster up. Point kubectl at it with:"
echo "    export KUBECONFIG=${KUBECONFIG_FILE}"
echo ""
log "Next: build + load images and deploy"
echo "    (cd ${PROJECT_ROOT} && ./scripts/build-images.sh)"
echo "    ${MP_ROOT}/scripts/load-images.sh"
echo "    ${MP_ROOT}/scripts/deploy.sh"
