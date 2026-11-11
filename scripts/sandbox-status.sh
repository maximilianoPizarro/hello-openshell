#!/bin/bash
# Show who the workspace is and what quota the project has.
# Run inside OpenShift Dev Spaces. Nothing here is created.
set -euo pipefail

echo "user: $(oc whoami)"
echo "project: $(oc project -q)"
echo
echo "=== quota ==="
oc get quota,limitrange
echo
echo "=== pods ==="
oc get pods
if oc api-resources --api-group=kubevirt.io -o name 2>/dev/null | grep -q '^virtualmachines$'; then
  echo
  echo "=== virtual machines ==="
  oc get vm,vmi,dv,svc -l app.kubernetes.io/part-of=hello-openshell
fi
