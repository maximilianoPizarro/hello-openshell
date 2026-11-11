#!/bin/bash
# From the Dev Spaces workspace, show the VM, the OpenShell sandbox, and minikube.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=sandbox-vm-lib.sh
source "${ROOT}/scripts/sandbox-vm-lib.sh"

echo "=== openshift ==="
oc get vm,vmi,dv,svc,pod -l app.kubernetes.io/part-of=hello-openshell || true

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
sandbox_vm_ssh 'sudo minikube status; echo; sudo kubectl get pods -A; echo; echo === openshell-0 ===; sudo kubectl logs -n openshell openshell-0 --tail=40; echo; echo === model-check agent ===; sudo kubectl logs -n openshell default--model-check -c agent --tail=40; echo; echo === model-check supervisor ===; sudo kubectl logs -n openshell default--model-check -c supervisor --tail=40; echo; echo === gateway unit ===; sudo journalctl -u hello-openshell-gateway -n 20 --no-pager' || true
