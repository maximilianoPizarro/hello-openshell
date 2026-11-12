#!/bin/bash
# From the Dev Spaces workspace, create one OpenShell sandbox on the
# gateway inside the guest (minikube or MicroShift).
# SANDBOX_GATEWAY=minikube|microshift (default minikube).
set -euo pipefail

SANDBOX_GATEWAY="${SANDBOX_GATEWAY:-minikube}"
export SANDBOX_GATEWAY
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "${ROOT}/scripts/install-openshell-cli.sh"
export PATH="${HOME}/.local/bin:${PATH}"

if [ "${SANDBOX_GATEWAY}" = "microshift" ]; then
  bash "${ROOT}/scripts/sandbox-rhel-connect.sh"
else
  bash "${ROOT}/scripts/sandbox-vm-connect.sh"
fi

cd "${ROOT}"
openshell gateway select "${SANDBOX_GATEWAY}"
openshell sandbox delete model-check >/dev/null 2>&1 || true
openshell sandbox create \
  --name model-check \
  --from registry.access.redhat.com/hi/python:3.12 \
  --policy deploy/hi-python.policy.yaml \
  -- /usr/bin/python3.12 -c 'print("ok")'
openshell sandbox list
