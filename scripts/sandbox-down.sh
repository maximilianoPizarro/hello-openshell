#!/bin/bash
# Delete only objects this workshop labeled. The shared model is not touched.
set -euo pipefail

echo "project: $(oc project -q)"
oc delete all,secret,configmap,route,job \
  -l app.kubernetes.io/part-of=hello-openshell \
  --ignore-not-found
echo "Labeled hello-openshell objects are gone. The Dev Spaces workspace is still running."
