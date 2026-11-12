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

sandbox_ssh_host() {
  case "${1:-${SANDBOX_GATEWAY:-minikube}}" in
    microshift) echo "${RHEL_VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local" ;;
    *) echo "${SANDBOX_VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local" ;;
  esac
}

# Clean or a new disk issues a new guest SSH host key. accept-new still
# fails when the old key is already in known_hosts.
sandbox_forget_host_key() {
  local host="${1:?}"
  local kh="${SANDBOX_VM_CFG}/known_hosts"
  mkdir -p "${SANDBOX_VM_CFG}"
  if [ ! -f "${kh}" ]; then
    return 0
  fi
  echo "Forgetting SSH host key for ${host} (the guest was recreated)."
  ssh-keygen -R "${host}" -f "${kh}" >/dev/null 2>&1 || true
  rm -f "${kh}.old"
}

sandbox_ssh_host_key_changed() {
  printf '%s\n' "${1:-}" | grep -qiE 'Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED|Offending .+ key'
}

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
    microshift) echo "B1. Clean, then B2. Start RHEL VM and Ollama" ;;
    *) echo "A1. Clean, then A2. Start minikube VM and Ollama" ;;
  esac
}

sandbox_kubevirt_start() {
  local name="${1:?}"
  local status server start_code
  status="$(oc get vm "${name}" -o jsonpath='{.status.printableStatus}' 2>/dev/null || true)"
  case "${status}" in
    Running|Starting|Provisioning|WaitingForVolumeBinding|WaitingForReceiver)
      return 0
      ;;
    "")
      echo "VM ${name} is missing. Run the Start task first."
      return 1
      ;;
  esac
  echo "VM ${name} is ${status}. Starting it (Developer Sandbox stops Linux VMs after one hour)."
  mkdir -p "${SANDBOX_VM_CFG}"
  server="$(oc whoami --show-server)"
  start_code="$(curl -sS -o "${SANDBOX_VM_CFG}/${name}-start.json" -w "%{http_code}" -k -X PUT \
    -H "Authorization: Bearer $(oc whoami -t)" \
    -H "Content-Type: application/json" \
    -d '{}' \
    "${server}/apis/subresources.kubevirt.io/v1/namespaces/${SANDBOX_VM_NS}/virtualmachines/${name}/start" || true)"
  echo "start HTTP ${start_code}"
  case "${start_code}" in
    200|202|409) return 0 ;;
    *) return 1 ;;
  esac
}

sandbox_require_pull_secret() {
  local path="${SANDBOX_VM_CFG}/openshift-pull-secret"
  if [ ! -s "${path}" ]; then
    echo "B3 needs a Red Hat pull secret before Connect MicroShift."
    echo "Download it from https://console.redhat.com/openshift/install/pull-secret"
    echo "Save the JSON as ${path}"
    echo "chmod 600 ${path}"
    echo "Then run B3 again. Cloud-init can install RPMs without it; MicroShift cannot pull quay.io/openshift-release-dev."
    return 1
  fi
  if ! python3 - "${path}" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except Exception as exc:
    print("openshift-pull-secret is not JSON:", exc)
    sys.exit(1)
if not isinstance(data, dict) or not data.get("auths"):
    print("openshift-pull-secret has no auths object.")
    sys.exit(1)
PY
  then
    return 1
  fi
  return 0
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
if ! grep -qE '[[:space:]]host\.openshell\.internal([[:space:]]|$)' /etc/hosts; then
  echo "127.0.0.1 host.openshell.internal" >> /etc/hosts
fi
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --add-port=11434/tcp --permanent >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
fi
if command -v iptables >/dev/null 2>&1; then
  iptables -C INPUT -p tcp --dport 11434 -j ACCEPT >/dev/null 2>&1 || \
    iptables -I INPUT -p tcp --dport 11434 -j ACCEPT || true
fi
systemctl daemon-reload
systemctl enable hello-openshell-ollama.service
systemctl restart hello-openshell-ollama.service
sleep 1
python3 -c 'import socket; socket.create_connection(("127.0.0.1", 11434), 5)'
EOF
}

# Apply CPU Ollama while the guest disk clones, then wait before Ask.
sandbox_begin_ollama() {
  local root="${1:?}"
  local pid
  mkdir -p "${SANDBOX_VM_CFG}"
  echo "Starting CPU Ollama in this project so llama3.2:1b is ready before Ask."
  bash "${root}/scripts/sandbox-ollama-up.sh" >"${SANDBOX_VM_CFG}/ollama-up.log" 2>&1 &
  pid=$!
  echo "${pid}" > "${SANDBOX_VM_CFG}/ollama-up.pid"
  echo "Ollama pid ${pid}. Log: ${SANDBOX_VM_CFG}/ollama-up.log"
  sleep 8
  if kill -0 "${pid}" 2>/dev/null; then
    return 0
  fi
  if wait "${pid}"; then
    rm -f "${SANDBOX_VM_CFG}/ollama-up.pid"
    echo "Ollama is already ready."
    return 0
  fi
  echo "Ollama failed to start with the VM."
  cat "${SANDBOX_VM_CFG}/ollama-up.log" || true
  return 1
}

sandbox_finish_ollama() {
  local root="${1:?}"
  local pidfile="${SANDBOX_VM_CFG}/ollama-up.pid"
  local pid=""
  if [ -f "${pidfile}" ]; then
    pid="$(cat "${pidfile}")"
  fi
  if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
    echo "Waiting for Ollama started with the VM..."
    if wait "${pid}"; then
      rm -f "${pidfile}"
      echo "Ollama is ready."
      return 0
    fi
    echo "Background Ollama failed. Retrying in the foreground."
    tail -n 50 "${SANDBOX_VM_CFG}/ollama-up.log" || true
  fi
  bash "${root}/scripts/sandbox-ollama-up.sh"
  rm -f "${pidfile}"
}

sandbox_openshell_gateway_connected() {
  local name="${1:-${SANDBOX_GATEWAY:-minikube}}"
  export PATH="${HOME}/.local/bin:${PATH}"
  command -v openshell >/dev/null 2>&1 || return 1
  openshell gateway select "${name}" >/dev/null 2>&1 || return 1
  openshell status 2>/dev/null | grep -qi connected
}

# Re-adding a gateway wipes server-side profiles. Keep the existing entry
# when the tunnel is already up.
sandbox_openshell_register_gateway() {
  local name="${1:?}"
  export PATH="${HOME}/.local/bin:${PATH}"
  if sandbox_openshell_gateway_connected "${name}"; then
    echo "Gateway ${name} already connected."
    openshell status
    return 0
  fi
  if openshell gateway add https://127.0.0.1:8080 --local --name "${name}"; then
    :
  else
    openshell gateway remove "${name}" >/dev/null 2>&1 || true
    openshell gateway add https://127.0.0.1:8080 --local --name "${name}"
  fi
  openshell gateway select "${name}"
  openshell status
}

sandbox_openshell_ensure_ollama() {
  local root="${1:?}"
  local profile="${root}/deploy/ollama.profile.yaml"
  local lint_file
  export PATH="${HOME}/.local/bin:${PATH}"
  openshell gateway select "${SANDBOX_GATEWAY:-minikube}"
  if openshell profile get ollama >/dev/null 2>&1; then
    echo "profile ollama is on this gateway."
  else
    lint_file="$(mktemp)"
    if ! openshell profile lint -f "${profile}" >"${lint_file}" 2>&1; then
      if grep -qi "already exists" "${lint_file}"; then
        echo "CLI already has profile ollama. Re-importing onto this gateway."
        openshell profile delete ollama >/dev/null 2>&1 || true
        openshell profile rm ollama >/dev/null 2>&1 || true
      else
        cat "${lint_file}"
        rm -f "${lint_file}"
        return 1
      fi
    fi
    rm -f "${lint_file}"
    openshell profile import -f "${profile}"
  fi
  if openshell provider get ollama >/dev/null 2>&1; then
    echo "provider ollama exists."
  else
    openshell provider create --name ollama --type ollama
  fi
}

# Kubernetes sandboxes have no DNS. OpenShell injects host.openshell.internal
# only when server.hostGatewayIP is set (the IP pods use to reach the guest).
sandbox_vm_ensure_host_gateway_ip() {
  sandbox_gateway_ssh sudo -n bash -s <<'EOF'
set -eu
MARKER=/var/lib/hello-openshell
mkdir -p "${MARKER}"
ip=""
if [ -x /usr/local/bin/minikube ]; then
  export HOME=/root KUBECONFIG=/root/.kube/config PATH=/usr/local/bin:/usr/bin:/bin
  kube() { kubectl "$@"; }
  ip="$(minikube ssh -- 'getent ahostsv4 host.minikube.internal 2>/dev/null | awk "{print \$1; exit}"' 2>/dev/null | tr -d '\r' | head -1 || true)"
  if [ -z "${ip}" ]; then
    ip="$(ip -4 addr show podman0 2>/dev/null | awk '/inet / {print $2; exit}' | cut -d/ -f1 || true)"
  fi
else
  export HOME=/root PATH=/usr/local/bin:/usr/bin:/bin
  KUBECONFIG="$(find /var/lib/microshift/resources -name kubeconfig 2>/dev/null | head -1)"
  export KUBECONFIG
  kube() { oc "$@"; }
  ip="$(kube get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)"
  if [ -z "${ip}" ]; then
    ip="$(hostname -I | awk '{print $1}')"
  fi
fi
if [ -z "${ip}" ]; then
  echo "Could not detect the host IP for host.openshell.internal."
  exit 1
fi
echo "${ip}" > "${MARKER}/host-gateway-ip"
chmod 644 "${MARKER}/host-gateway-ip"
current="$(kube -n openshell get statefulset openshell -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>/dev/null | awk -F= '$1=="OPENSHELL_HOST_GATEWAY_IP"{print $2; exit}')"
if [ "${current}" = "${ip}" ]; then
  echo "OpenShell hostGatewayIP is already ${ip}."
  exit 0
fi
echo "Setting OPENSHELL_HOST_GATEWAY_IP=${ip} so sandbox pods resolve host.openshell.internal."
kube -n openshell set env statefulset/openshell "OPENSHELL_HOST_GATEWAY_IP=${ip}"
kube -n openshell rollout status statefulset/openshell --timeout=180s || true
EOF
}

sandbox_guest_host_gateway_ip() {
  sandbox_gateway_ssh "cat /var/lib/hello-openshell/host-gateway-ip 2>/dev/null || true" | tr -d '\r\n'
}

sandbox_openshell_prepare_ask() {
  local root="${1:?}"
  sandbox_vm_ensure_ollama_proxy
  if ! sandbox_gateway_ssh 'python3 -c "import socket; socket.create_connection((\"127.0.0.1\", 11434), 5)"'; then
    echo "Guest :11434 did not accept connections. The sandbox cannot reach Ollama."
    sandbox_gateway_ssh 'sudo -n systemctl status hello-openshell-ollama --no-pager' || true
    return 1
  fi
  sandbox_vm_ensure_host_gateway_ip
  sandbox_openshell_ensure_ollama "${root}"
}
