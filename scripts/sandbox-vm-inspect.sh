#!/bin/bash
# From the Dev Spaces workspace, show the VM, the OpenShell sandbox, and
# the guest cluster (minikube or MicroShift).
# SANDBOX_GATEWAY=minikube|microshift (default: whichever VM is Running).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=sandbox-vm-lib.sh
source "${ROOT}/scripts/sandbox-vm-lib.sh"

if [ -z "${SANDBOX_GATEWAY:-}" ]; then
  fedora="$(oc get vm "${SANDBOX_VM_NAME}" -o jsonpath='{.status.printableStatus}' 2>/dev/null || true)"
  rhel="$(oc get vm "${RHEL_VM_NAME}" -o jsonpath='{.status.printableStatus}' 2>/dev/null || true)"
  if [ "${fedora}" = "Running" ]; then
    SANDBOX_GATEWAY=minikube
  elif [ "${rhel}" = "Running" ]; then
    SANDBOX_GATEWAY=microshift
  else
    SANDBOX_GATEWAY=minikube
  fi
fi
export SANDBOX_GATEWAY

echo "=== openshift ==="
oc get vm,vmi,dv,svc,pod,deploy -l app.kubernetes.io/part-of=hello-openshell || true
echo
echo "=== ollama ==="
export MSYS_NO_PATHCONV=1
oc get deploy,svc,pod -l app.kubernetes.io/name=ollama || true
if oc get deploy ollama >/dev/null 2>&1; then
  oc exec deploy/ollama -- ollama list 2>/dev/null || true
fi
if [ -f "${SANDBOX_VM_KEY}" ]; then
  echo "--- $(sandbox_gateway_vm) :11434 (host.openshell.internal) ---"
  sandbox_gateway_ssh 'sudo -n systemctl is-active hello-openshell-ollama 2>/dev/null; python3 -c "import socket; socket.create_connection((\"127.0.0.1\", 11434), 2)" && echo 11434=open || echo 11434=closed' || true
fi

echo
echo "=== openshell ==="
export PATH="${HOME}/.local/bin:${PATH}"
if command -v openshell >/dev/null 2>&1; then
  openshell gateway select "${SANDBOX_GATEWAY}" || true
  openshell status || true
  openshell sandbox list || true
  openshell logs model-check || true
  openshell policy get model-check --full || true
else
  echo "openshell is not on PATH. Run 1. Install OpenShell CLI."
fi

echo
echo "=== ${SANDBOX_GATEWAY} guest ==="
if [ ! -f "${SANDBOX_VM_KEY}" ]; then
  echo "No SSH key at ${SANDBOX_VM_KEY}. Run $(sandbox_gateway_start_hint) first."
  exit 0
fi
if [ "${SANDBOX_GATEWAY}" = "microshift" ]; then
  sandbox_rhel_ssh 'echo === microshift ===; sudo oc get nodes; echo; sudo oc get pods -A; echo; echo === openshell-0 ===; sudo oc logs -n openshell openshell-0 --tail=40; echo; echo === model-check agent ===; sudo oc logs -n openshell default--model-check -c agent --tail=40; echo; echo === gateway unit ===; sudo journalctl -u hello-openshell-gateway -n 20 --no-pager' || true
else
  sandbox_vm_ssh 'sudo minikube status; echo; sudo kubectl get pods -A; echo; echo === openshell-0 ===; sudo kubectl logs -n openshell openshell-0 --tail=40; echo; echo === model-check agent ===; sudo kubectl logs -n openshell default--model-check -c agent --tail=40; echo; echo === gateway unit ===; sudo journalctl -u hello-openshell-gateway -n 20 --no-pager' || true
fi
