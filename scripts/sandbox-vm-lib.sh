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

# kubectl port-forward exits when its API connection drops. A unit brings it back.
sandbox_vm_ensure_gateway() {
  sandbox_vm_ssh sudo -n bash -s <<'EOF'
set -eu
export HOME=/root KUBECONFIG=/root/.kube/config PATH=/usr/local/bin:/usr/bin:/bin
if python3 -c 'import socket; socket.create_connection(("127.0.0.1", 8080), 2)' 2>/dev/null; then
  exit 0
fi
cat >/etc/systemd/system/hello-openshell-gateway.service <<'UNIT'
[Unit]
Description=OpenShell gateway port-forward
After=network-online.target
[Service]
Environment=HOME=/root
Environment=KUBECONFIG=/root/.kube/config
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/local/bin/kubectl -n openshell port-forward --address 0.0.0.0 svc/openshell 8080:8080
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable hello-openshell-gateway.service
systemctl restart hello-openshell-gateway.service
sleep 2
python3 -c 'import socket; socket.create_connection(("127.0.0.1", 8080), 2)'
EOF
}
