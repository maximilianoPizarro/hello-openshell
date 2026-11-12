#!/bin/bash
# Shared helpers for the Developer Sandbox minikube VM.
# Source this file. Do not execute it.

if [ -n "${SANDBOX_VM_LIB:-}" ]; then
  return 0
fi
SANDBOX_VM_LIB=1

SANDBOX_VM_NAME=minikube-vm
RHEL_VM_NAME=rhel-vm
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

sandbox_rhel_ssh() {
  ssh -i "${SANDBOX_VM_KEY}" \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="${SANDBOX_VM_CFG}/known_hosts" \
    -o ConnectTimeout=8 \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=4 \
    "cloud-user@${RHEL_VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local" \
    "$@"
}

sandbox_gateway_ssh() {
  case "${SANDBOX_GATEWAY:-minikube}" in
    microshift) sandbox_rhel_ssh "$@" ;;
    minikube) sandbox_vm_ssh "$@" ;;
    *)
      echo "SANDBOX_GATEWAY must be minikube or microshift (got ${SANDBOX_GATEWAY:-})."
      return 1
      ;;
  esac
}

sandbox_gateway_vm() {
  case "${SANDBOX_GATEWAY:-minikube}" in
    microshift) echo "${RHEL_VM_NAME}" ;;
    *) echo "${SANDBOX_VM_NAME}" ;;
  esac
}

sandbox_gateway_start_hint() {
  case "${SANDBOX_GATEWAY:-minikube}" in
    microshift) echo "B1. Clean, then B2. Start RHEL VM" ;;
    *) echo "A1. Clean, then A2. Start minikube VM" ;;
  esac
}

# kubectl port-forward exits when its API connection drops. A unit brings it back.
sandbox_vm_ensure_gateway() {
  sandbox_vm_ssh sudo -n bash -s <<'EOF'
set -eu
export HOME=/root KUBECONFIG=/root/.kube/config PATH=/usr/local/bin:/usr/bin:/bin
if python3 -c 'import socket; socket.create_connection(("127.0.0.1", 8080), 2)' 2>/dev/null; then
  exit 0
fi
if [ ! -x /usr/local/bin/kubectl ]; then
  echo "kubectl is not installed yet. minikube is still booting."
  exit 1
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

# Sandboxes have no network. The supervisor dials host.openshell.internal:11434
# on the guest (Fedora minikube or RHEL MicroShift). That port is a TCP proxy
# to Ollama in this project, so the 1b model does not compete for the guest's 8Gi.
sandbox_vm_ensure_ollama_proxy() {
  local upstream guest
  guest="$(sandbox_gateway_vm)"
  upstream="$(oc get svc ollama -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
  if [ -z "${upstream}" ]; then
    echo "Service ollama has no ClusterIP. Start Ollama in this project first."
    return 1
  fi
  echo "${guest} :11434 -> ${upstream}:11434 (Ollama in ${SANDBOX_VM_NS})"
  sandbox_gateway_ssh sudo -n bash -s <<EOF
set -eu
cat >/usr/local/bin/hello-openshell-ollama-proxy.py <<'PY'
#!/usr/bin/python3
import socket
import sys
import threading

upstream = sys.argv[1]
port = int(sys.argv[2]) if len(sys.argv) > 2 else 11434


def pipe(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def handle(client):
    try:
        remote = socket.create_connection((upstream, port), 10)
    except OSError:
        client.close()
        return
    t = threading.Thread(target=pipe, args=(client, remote), daemon=True)
    t.start()
    pipe(remote, client)
    t.join()
    client.close()
    try:
        remote.close()
    except OSError:
        pass


srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("0.0.0.0", port))
srv.listen(32)
while True:
    client, _ = srv.accept()
    threading.Thread(target=handle, args=(client,), daemon=True).start()
PY
chmod 755 /usr/local/bin/hello-openshell-ollama-proxy.py
cat >/etc/systemd/system/hello-openshell-ollama.service <<UNIT
[Unit]
Description=Proxy host.openshell.internal:11434 to OpenShift Ollama
After=network-online.target
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/hello-openshell-ollama-proxy.py ${upstream} 11434
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable hello-openshell-ollama.service
systemctl restart hello-openshell-ollama.service
sleep 1
python3 -c 'import socket; socket.create_connection(("127.0.0.1", 11434), 5)'
EOF
}
