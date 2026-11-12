#!/bin/bash
# Delete the workshop OpenShell sandboxes on the selected gateway.
# Does not stop the guest VM or Ollama.
# SANDBOX_GATEWAY=minikube|microshift (default minikube).
set -euo pipefail

SANDBOX_GATEWAY="${SANDBOX_GATEWAY:-minikube}"
export SANDBOX_GATEWAY
export PATH="${HOME}/.local/bin:${PATH}"

if [[ "${SANDBOX_GATEWAY}" != "minikube" && "${SANDBOX_GATEWAY}" != "microshift" ]]; then
  echo "SANDBOX_GATEWAY must be minikube or microshift."
  exit 1
fi

if ! command -v openshell >/dev/null 2>&1; then
  echo "openshell is not on PATH. Run 1. Install OpenShell CLI."
  exit 1
fi

NAMES=(hello-ask hello-agent hello-turns model-check)

echo "Deleting OpenShell sandboxes on ${SANDBOX_GATEWAY}. The guest VM and Ollama stay up."
if ! openshell gateway select "${SANDBOX_GATEWAY}"; then
  case "${SANDBOX_GATEWAY}" in
    microshift) hint="B3. Connect MicroShift" ;;
    *) hint="A3. Connect minikube gateway" ;;
  esac
  echo "Gateway ${SANDBOX_GATEWAY} is not connected. Run ${hint} first. Do not Clean."
  exit 1
fi

echo "=== before ==="
openshell sandbox list || true
for name in "${NAMES[@]}"; do
  echo "Deleting ${name}"
  openshell sandbox delete "${name}" || true
done
echo "=== after ==="
openshell sandbox list || true
echo "Sandboxes are gone. minikube-vm / rhel-vm and Ollama were not deleted."
