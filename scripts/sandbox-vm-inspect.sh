#!/bin/bash
# From the Dev Spaces workspace, show the VM, the OpenShell sandbox, and minikube.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=sandbox-vm-lib.sh
source "${ROOT}/scripts/sandbox-vm-lib.sh"

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
  echo "--- fedora :11434 (host.openshell.internal) ---"
  sandbox_vm_ssh 'sudo -n systemctl is-active hello-openshell-ollama 2>/dev/null; python3 -c "import socket; socket.create_connection((\"127.0.0.1\", 11434), 2)" && echo 11434=open || echo 11434=closed' || true
fi

echo
echo "=== openshell ==="
export PATH="${HOME}/.local/bin:${PATH}"
if command -v openshell >/dev/null 2>&1; then
  openshell gateway select minikube || true
  openshell status || true
  openshell sandbox list || true
  openshell logs model-check || true
  openshell policy get model-check --full || true
else
  echo "openshell is not on PATH. Run 1. Install OpenShell CLI."
fi

echo
echo "=== minikube ==="
if [ ! -f "${SANDBOX_VM_KEY}" ]; then
  echo "No SSH key at ${SANDBOX_VM_KEY}. Run 3. Start minikube VM first."
  exit 0
fi
sandbox_vm_ssh 'sudo minikube status; echo; sudo kubectl get pods -A; echo; echo === openshell-0 ===; sudo kubectl logs -n openshell openshell-0 --tail=40; echo; echo === model-check agent ===; sudo kubectl logs -n openshell default--model-check -c agent --tail=40; echo; echo === gateway unit ===; sudo journalctl -u hello-openshell-gateway -n 20 --no-pager' || true
