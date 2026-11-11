#!/bin/bash
# Shared helpers for the Developer Sandbox minikube VM.
# Source this file. Do not execute it.

if [ -n "${SANDBOX_VM_LIB:-}" ]; then
  return 0
fi
SANDBOX_VM_LIB=1

SANDBOX_VM_NAME=minikube-vm
SANDBOX_VM_CFG="${HOME}/.config/hello-openshell"
SANDBOX_VM_KEY="${SANDBOX_VM_CFG}/minikube_ed25519"
SANDBOX_VM_NS="$(oc project -q)"

sandbox_vm_ssh() {
  ssh -i "${SANDBOX_VM_KEY}" \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="${SANDBOX_VM_CFG}/known_hosts" \
    -o ConnectTimeout=8 \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=4 \
    "fedora@${SANDBOX_VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local" \
    "$@"
}
