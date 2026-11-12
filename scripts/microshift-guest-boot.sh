#!/bin/bash
# Install MicroShift and the OpenShell gateway on the RHEL sandbox guest.
# Run as root. The catalog image has no subscription, so BaseOS packages
# come from AlmaLinux 9 and MicroShift comes from mirror.openshift.com.
set -euo pipefail

export HOME=/root
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

MARKER=/var/lib/hello-openshell
PULL_SECRET=/etc/crio/openshift-pull-secret
VALUES="${MARKER}/openshift-scc-values.yaml"
KUBECONFIG=""

mkdir -p "${MARKER}"
exec 9>"${MARKER}/boot.lock"
if ! flock -w 2400 9; then
  echo "Timed out waiting for another microshift-guest-boot.sh."
  exit 1
fi

have_pull_secret() {
  python3 - <<'PY'
import json, sys
from pathlib import Path
path = Path("/etc/crio/openshift-pull-secret")
if not path.is_file() or path.stat().st_size == 0:
    sys.exit(1)
data = json.loads(path.read_text())
sys.exit(0 if data.get("auths") else 1)
PY
}

kube() {
  if [ -z "${KUBECONFIG}" ]; then
    KUBECONFIG="$(find /var/lib/microshift/resources -name kubeconfig | head -1)"
  fi
  export KUBECONFIG
  oc "$@"
}

pin_node_name() {
  local ip4 name
  ip4="$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1)"
  name="$(hostname -s)"
  if [ -n "${ip4}" ] && ! grep -qE "^${ip4}[[:space:]]+${name}([[:space:]]|$)" /etc/hosts; then
    echo "${ip4} ${name}" >> /etc/hosts
  fi
}

install_rpms() {
  if rpm -q microshift >/dev/null 2>&1; then
    echo "microshift is already installed."
    return 0
  fi
  cat >/etc/yum.repos.d/microshift-sandbox.repo <<'EOF'
[microshift-4.22]
name=MicroShift 4.22
baseurl=https://mirror.openshift.com/pub/openshift-v4/x86_64/microshift/ocp/latest-4.22/el9/os/
enabled=0
gpgcheck=0
[openshift-4.22-deps]
name=OpenShift 4.22 dependencies
baseurl=https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rpms/4.22-el9-beta/
enabled=0
gpgcheck=0
[alma-baseos]
name=AlmaLinux 9 BaseOS
baseurl=https://repo.almalinux.org/almalinux/9/BaseOS/x86_64/os/
enabled=0
gpgcheck=0
[alma-appstream]
name=AlmaLinux 9 AppStream
baseurl=https://repo.almalinux.org/almalinux/9/AppStream/x86_64/os/
enabled=0
gpgcheck=0
EOF
  rm -rf /tmp/ms-rpms
  mkdir -p /tmp/ms-rpms
  dnf install -y --downloadonly --downloaddir=/tmp/ms-rpms \
    --disablerepo='*' \
    --enablerepo='microshift-4.22,openshift-4.22-deps,alma-baseos,alma-appstream' \
    microshift
  rm -f /tmp/ms-rpms/*.i686.rpm
  local i
  for i in $(seq 1 30); do
    if rpm -Uvh --replacefiles --oldpackage /tmp/ms-rpms/*.rpm; then
      rpm -q microshift cri-o
      return 0
    fi
    echo "rpm transaction locked or failed. Waiting."
    sleep 20
  done
  echo "rpm -Uvh could not get /var/lib/rpm/.rpm.lock."
  return 1
}

configure_guest() {
  mkdir -p /etc/microshift/config.d
  cat >/etc/microshift/config.d/10-storage.yaml <<'EOF'
storage:
  driver: none
EOF
  pin_node_name
}

wait_for_node() {
  local i ready
  for i in $(seq 1 90); do
    ready="$(kube get nodes --no-headers 2>/dev/null | awk '{print $2; exit}' || true)"
    echo "node=${ready:-unknown}"
    if [ "${ready}" = "Ready" ]; then
      return 0
    fi
    sleep 10
  done
  echo "MicroShift node did not become Ready."
  journalctl -u microshift -n 40 --no-pager || true
  return 1
}

gateway_ready() {
  local ready
  ready="$(kube -n openshell get pod openshell-0 -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)"
  [ "${ready}" = "true" ]
}

install_gateway() {
  if [ ! -s "${VALUES}" ]; then
    echo "Missing ${VALUES}. The connect script copies deploy/openshift-scc-values.yaml there."
    return 1
  fi
  if [ ! -x /usr/local/bin/helm ]; then
    curl -fL -o /tmp/helm.tgz https://get.helm.sh/helm-v3.22.1-linux-amd64.tar.gz
    tar -xzf /tmp/helm.tgz -C /tmp
    install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
  fi
  if ! kube get crd sandboxes.agents.x-k8s.io >/dev/null 2>&1; then
    kube apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v1.0.10/sandbox.yaml
  fi
  kube -n agent-sandbox-system rollout status deployment/agent-sandbox-controller --timeout=180s
  install -d -m 770 /var/lib/hello-openshell/openshell-data
  if ! kube get pv openshell-data >/dev/null 2>&1; then
    cat <<'EOF' | kube apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: openshell-data
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /var/lib/hello-openshell/openshell-data
    type: DirectoryOrCreate
EOF
  fi
  if ! kube -n openshell get statefulset openshell >/dev/null 2>&1; then
    helm upgrade --install openshell \
      oci://ghcr.io/nvidia/openshell/helm-chart \
      --version 0.1.8 \
      --namespace openshell --create-namespace \
      --values "${VALUES}" \
      --set dataStorageClass=manual
  fi
  local uid
  uid="$(kube get namespace openshell -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}' | cut -d/ -f1)"
  if [ -n "${uid}" ]; then
    chown "${uid}:${uid}" /var/lib/hello-openshell/openshell-data
    chmod 770 /var/lib/hello-openshell/openshell-data
    chcon -t container_file_t /var/lib/hello-openshell/openshell-data || true
  fi
  if kube -n openshell get pvc openshell-data-openshell-0 >/dev/null 2>&1; then
    local phase
    phase="$(kube -n openshell get pvc openshell-data-openshell-0 -o jsonpath='{.status.phase}')"
    if [ "${phase}" != "Bound" ]; then
      kube -n openshell patch pvc openshell-data-openshell-0 --type merge -p '{"spec":{"storageClassName":"manual"}}' || true
    fi
  fi
  kube -n openshell delete pod openshell-0 --wait=false >/dev/null 2>&1 || true
  local i ready
  for i in $(seq 1 36); do
    ready="$(kube -n openshell get pod openshell-0 -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)"
    echo "gateway ready=${ready:-false}"
    if [ "${ready}" = "true" ]; then
      return 0
    fi
    sleep 5
  done
  echo "OpenShell gateway pod did not become ready."
  kube -n openshell describe pod openshell-0 | tail -30 || true
  return 1
}

publish_gateway() {
  cat >/etc/systemd/system/hello-openshell-gateway.service <<'UNIT'
[Unit]
Description=OpenShell gateway port-forward
After=microshift.service
[Service]
Environment=HOME=/root
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/bin/bash -c 'export KUBECONFIG=$(find /var/lib/microshift/resources -name kubeconfig | head -1); exec oc -n openshell port-forward --address 127.0.0.1 svc/openshell 8080:8080'
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable hello-openshell-gateway.service
  if ! python3 -c 'import socket; socket.create_connection(("127.0.0.1", 8080), 2)' 2>/dev/null; then
    systemctl restart hello-openshell-gateway.service
  fi
  local i
  for i in $(seq 1 15); do
    if python3 -c 'import socket; socket.create_connection(("127.0.0.1", 8080), 2)' 2>/dev/null; then
      break
    fi
    sleep 2
  done
  python3 -c 'import socket; socket.create_connection(("127.0.0.1", 8080), 2)'
  install -d -o cloud-user -g cloud-user -m 700 /home/cloud-user/openshell-client
  local k
  for k in ca.crt tls.crt tls.key; do
    kube -n openshell get secret openshell-client-tls -o go-template="{{index .data \"${k}\"}}" | base64 -d > "/home/cloud-user/openshell-client/${k}"
    test -s "/home/cloud-user/openshell-client/${k}"
  done
  chown cloud-user:cloud-user /home/cloud-user/openshell-client/*
  chmod 644 /home/cloud-user/openshell-client/ca.crt /home/cloud-user/openshell-client/tls.crt
  chmod 600 /home/cloud-user/openshell-client/tls.key
  date -Is > "${MARKER}/ready"
  rm -f "${MARKER}/needs-pull-secret"
}

install_rpms
configure_guest
if have_pull_secret; then
  rm -f "${MARKER}/needs-pull-secret"
else
  echo "MicroShift needs a pull secret at ${PULL_SECRET}."
  echo "Copy ~/.config/hello-openshell/openshift-pull-secret with the connect task, then run it again."
  date -Is > "${MARKER}/needs-pull-secret"
  exit 2
fi
systemctl enable --now crio
systemctl enable --now microshift
wait_for_node
if ! gateway_ready; then
  install_gateway
fi
publish_gateway
echo MICROSHIFT_READY
