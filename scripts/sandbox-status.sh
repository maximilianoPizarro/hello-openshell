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
