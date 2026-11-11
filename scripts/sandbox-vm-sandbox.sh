#!/bin/bash
# From the Dev Spaces workspace, create one OpenShell sandbox on the
# gateway that cloud-init installed inside the Fedora VM.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "${ROOT}/scripts/install-openshell-cli.sh"
export PATH="${HOME}/.local/bin:${PATH}"
bash "${ROOT}/scripts/sandbox-vm-connect.sh"

cd "${ROOT}"
openshell gateway select minikube
openshell sandbox delete model-check >/dev/null 2>&1 || true
openshell sandbox create \
  --name model-check \
  --from registry.access.redhat.com/hi/python:3.12 \
  --policy deploy/hi-python.policy.yaml \
  -- /usr/bin/python3.12 -c 'print("ok")'
openshell sandbox list
