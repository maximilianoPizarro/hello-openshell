#!/bin/bash
# Point the OpenShell CLI at the gateway inside the Fedora minikube VM.
# The tunnel is local because the server certificate includes localhost.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=sandbox-vm-lib.sh
source "${ROOT}/scripts/sandbox-vm-lib.sh"

if [ ! -f "${SANDBOX_VM_KEY}" ]; then
  echo "No SSH key at ${SANDBOX_VM_KEY}. Run scripts/sandbox-vm-up.sh first."
  exit 1
fi

bash "${ROOT}/scripts/install-openshell-cli.sh"
export PATH="${HOME}/.local/bin:${PATH}"

mkdir -p "${SANDBOX_VM_CFG}"
deadline=$((SECONDS + 40 * 60))
retried=0
echo "Waiting until the guest publishes the gateway. First boot can take most of the hour."

while [ "${SECONDS}" -lt "${deadline}" ]; do
  vm_status="$(oc get vm "${SANDBOX_VM_NAME}" -o jsonpath='{.status.printableStatus}' 2>/dev/null || true)"
  disk_phase="$(oc get dv minikube-vm-disk -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  echo "vm=${vm_status:-unknown} disk=${disk_phase:-unknown}"
  if [ "${disk_phase}" = "Failed" ] || [ "${disk_phase}" = "ImportInProgress" ]; then
    :
  fi
  if [ "${disk_phase}" = "Failed" ]; then
    oc describe dv minikube-vm-disk || true
    exit 1
  fi

  if err="$(sandbox_vm_ssh true 2>&1)"; then
    if ! sandbox_vm_ssh "python3 -c 'import socket; socket.create_connection((\"127.0.0.1\", 8080), 2)'" 2>/dev/null; then
      if sandbox_vm_ssh "test -x /usr/local/bin/kubectl"; then
        echo "127.0.0.1:8080 is closed in the guest. Restarting the gateway port-forward."
        if ! sandbox_vm_ensure_gateway; then
          echo "Port-forward did not start."
          sandbox_vm_ssh "sudo -n env PATH=/usr/local/bin:/usr/bin:/bin kubectl -n openshell get pods; echo ---; sudo -n journalctl -u hello-openshell-gateway -n 30 --no-pager; echo ---; sudo -n tail -n 30 /var/log/cloud-init-output.log" || true
        fi
      fi
    fi
    if sandbox_vm_ssh "test -f /var/lib/hello-openshell/ready && python3 -c 'import socket; socket.create_connection((\"127.0.0.1\", 8080), 2)'"; then
      echo "Guest gateway is up."
      break
    fi
    if sandbox_vm_ssh "test -f /var/lib/hello-openshell/failed"; then
      if [ "${retried}" -eq 0 ]; then
        echo "Guest boot failed once. Starting the gateway port-forward again."
        sandbox_vm_ensure_gateway || true
        retried=1
      else
        echo "Guest boot failed:"
        sandbox_vm_ssh "cat /var/lib/hello-openshell/failed; echo; sudo tail -n 80 /var/log/cloud-init-output.log" || true
        exit 1
      fi
    else
      sandbox_vm_ssh "sudo tail -n 15 /var/log/cloud-init-output.log" || true
    fi
  else
    if printf '%s\n' "${err}" | grep -q "Permission denied"; then
      echo "This workspace key is not authorized in the VM."
      echo "Cloud-init keeps the key from the first boot. Run the Clean task, then Start minikube VM."
      exit 1
    fi
    printf '%s\n' "${err}" | tail -n 3
  fi
  sleep 20
done

if ! sandbox_vm_ssh "test -f /var/lib/hello-openshell/ready"; then
  echo "Timed out waiting for /var/lib/hello-openshell/ready."
  oc describe vm "${SANDBOX_VM_NAME}" || true
  exit 1
fi

dest="${HOME}/.config/openshell/gateways/minikube/mtls"
mkdir -p "${dest}"
scp -i "${SANDBOX_VM_KEY}" \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="${SANDBOX_VM_CFG}/known_hosts" \
  "fedora@${SANDBOX_VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local:openshell-client/ca.crt" \
  "fedora@${SANDBOX_VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local:openshell-client/tls.crt" \
  "fedora@${SANDBOX_VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local:openshell-client/tls.key" \
  "${dest}/"
chmod 644 "${dest}/ca.crt" "${dest}/tls.crt"
chmod 600 "${dest}/tls.key"

pidfile="${SANDBOX_VM_CFG}/tunnel.pid"
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
    "fedora@${SANDBOX_VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local" \
    >> "${SANDBOX_VM_CFG}/tunnel.log" 2>&1 < /dev/null &
  echo $! > "${pidfile}"
  sleep 2
  if ! kill -0 "$(cat "${pidfile}")" 2>/dev/null; then
    echo "SSH tunnel exited."
    cat "${SANDBOX_VM_CFG}/tunnel.log" || true
    exit 1
  fi
fi

openshell gateway remove minikube >/dev/null 2>&1 || true
openshell gateway add https://127.0.0.1:8080 --local --name minikube
openshell gateway select minikube
openshell status
