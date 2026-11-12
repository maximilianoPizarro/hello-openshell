#!/bin/bash
# Point the OpenShell CLI at the gateway inside the RHEL MicroShift VM.
# The tunnel is local because the server certificate includes localhost.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=sandbox-vm-lib.sh
source "${ROOT}/scripts/sandbox-vm-lib.sh"

RHEL_VM_NAME=rhel-vm
RHEL_PULL_SECRET="${SANDBOX_VM_CFG}/openshift-pull-secret"

if [ ! -f "${SANDBOX_VM_KEY}" ]; then
  echo "No SSH key at ${SANDBOX_VM_KEY}. Run B2. Start RHEL VM and Ollama first."
  exit 1
fi

if ! sandbox_require_pull_secret; then
  exit 1
fi

bash "${ROOT}/scripts/install-openshell-cli.sh"
export PATH="${HOME}/.local/bin:${PATH}"

rhel_ssh() {
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

mkdir -p "${SANDBOX_VM_CFG}"
deadline=$((SECONDS + 40 * 60))
echo "Waiting until the RHEL guest publishes the MicroShift gateway."

while [ "${SECONDS}" -lt "${deadline}" ]; do
  vm_status="$(oc get vm "${RHEL_VM_NAME}" -o jsonpath='{.status.printableStatus}' 2>/dev/null || true)"
  disk_phase="$(oc get dv rhel-vm-disk -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  echo "vm=${vm_status:-unknown} disk=${disk_phase:-unknown}"
  if [ "${disk_phase}" = "Failed" ]; then
    oc describe dv rhel-vm-disk || true
    exit 1
  fi
  if [ "${vm_status}" = "Stopped" ] || [ "${vm_status}" = "Paused" ]; then
    sandbox_kubevirt_start "${RHEL_VM_NAME}" || true
    sleep 20
    continue
  fi
  if [ -z "${vm_status}" ]; then
    echo "VM ${RHEL_VM_NAME} is missing. Run B2. Start RHEL VM and Ollama first."
    exit 1
  fi

  if err="$(rhel_ssh true 2>&1)"; then
    rhel_ssh sudo -n install -d -m 755 /etc/crio /var/lib/hello-openshell
    scp -q -i "${SANDBOX_VM_KEY}" \
      -o IdentitiesOnly=yes \
      -o UserKnownHostsFile="${SANDBOX_VM_CFG}/known_hosts" \
      "${RHEL_PULL_SECRET}" \
      "cloud-user@${RHEL_VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local:/tmp/openshift-pull-secret"
    rhel_ssh sudo -n install -m 600 /tmp/openshift-pull-secret /etc/crio/openshift-pull-secret
    rhel_ssh rm -f /tmp/openshift-pull-secret
    scp -q -i "${SANDBOX_VM_KEY}" \
      -o IdentitiesOnly=yes \
      -o UserKnownHostsFile="${SANDBOX_VM_CFG}/known_hosts" \
      "${ROOT}/scripts/microshift-guest-boot.sh" \
      "${ROOT}/deploy/openshift-scc-values.yaml" \
      "cloud-user@${RHEL_VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local:/tmp/"
    rhel_ssh sudo -n install -m 755 /tmp/microshift-guest-boot.sh /usr/local/sbin/microshift-guest-boot.sh
    rhel_ssh sudo -n install -m 644 /tmp/openshift-scc-values.yaml /var/lib/hello-openshell/openshift-scc-values.yaml
    set +e
    rhel_ssh sudo -n bash /usr/local/sbin/microshift-guest-boot.sh
    code=$?
    set -e
    if [ "${code}" -eq 0 ] && rhel_ssh "test -f /var/lib/hello-openshell/ready && python3 -c 'import socket; socket.create_connection((\"127.0.0.1\", 8080), 2)'"; then
      echo "Guest gateway is up."
      break
    fi
    if [ "${code}" -eq 2 ] || rhel_ssh "test -f /var/lib/hello-openshell/needs-pull-secret"; then
      echo "The guest still has no usable pull secret at /etc/crio/openshift-pull-secret."
      echo "Save a Red Hat pull secret as ${RHEL_PULL_SECRET} and run B3 again."
      echo "Download: https://console.redhat.com/openshift/install/pull-secret"
      exit 1
    fi
    echo "Guest boot has not finished (exit ${code}). Waiting; cloud-init may still hold rpm."
    rhel_ssh "sudo -n tail -n 20 /var/log/cloud-init-output.log" || true
  else
    if printf '%s\n' "${err}" | grep -q "Permission denied"; then
      echo "This workspace key is not authorized in the VM."
      echo "Cloud-init keeps the key from the first boot. Run B1. Clean, then B2. Start RHEL VM."
      exit 1
    fi
    printf '%s\n' "${err}" | tail -n 3
  fi
  sleep 20
done

if ! rhel_ssh "test -f /var/lib/hello-openshell/ready"; then
  echo "Timed out waiting for /var/lib/hello-openshell/ready."
  oc describe vm "${RHEL_VM_NAME}" || true
  exit 1
fi

dest="${HOME}/.config/openshell/gateways/microshift/mtls"
mkdir -p "${dest}"
scp -i "${SANDBOX_VM_KEY}" \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="${SANDBOX_VM_CFG}/known_hosts" \
  "cloud-user@${RHEL_VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local:openshell-client/ca.crt" \
  "cloud-user@${RHEL_VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local:openshell-client/tls.crt" \
  "cloud-user@${RHEL_VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local:openshell-client/tls.key" \
  "${dest}/"
chmod 644 "${dest}/ca.crt" "${dest}/tls.crt"
chmod 600 "${dest}/tls.key"

pidfile="${SANDBOX_VM_CFG}/microshift-tunnel.pid"
if [ -f "${pidfile}" ] && kill -0 "$(cat "${pidfile}")" 2>/dev/null; then
  echo "SSH tunnel already running (pid $(cat "${pidfile}"))."
elif (echo >/dev/tcp/127.0.0.1/8080) >/dev/null 2>&1; then
  echo "127.0.0.1:8080 is already open. Stop that process before connecting the gateway."
  exit 1
else
  setsid ssh -i "${SANDBOX_VM_KEY}" \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="${SANDBOX_VM_CFG}/known_hosts" \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=4 \
    -o ExitOnForwardFailure=yes \
    -N -L "127.0.0.1:8080:127.0.0.1:8080" \
    "cloud-user@${RHEL_VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local" \
    >> "${SANDBOX_VM_CFG}/microshift-tunnel.log" 2>&1 < /dev/null &
  echo $! > "${pidfile}"
  sleep 2
  if ! kill -0 "$(cat "${pidfile}")" 2>/dev/null; then
    echo "SSH tunnel exited."
    cat "${SANDBOX_VM_CFG}/microshift-tunnel.log" || true
    exit 1
  fi
fi

export SANDBOX_GATEWAY=microshift
sandbox_openshell_register_gateway microshift
sandbox_openshell_prepare_ask "${ROOT}"
