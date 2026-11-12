#!/bin/bash
# Delete only objects this workshop labeled. The shared model is not touched.
set -euo pipefail

echo "project: $(oc project -q)"

for pidfile in \
  "${HOME}/.config/hello-openshell/tunnel.pid" \
  "${HOME}/.config/hello-openshell/microshift-tunnel.pid"
do
  if [ -f "${pidfile}" ]; then
    pid="$(cat "${pidfile}")"
    if [ -n "${pid}" ]; then
      kill "${pid}" 2>/dev/null || true
    fi
    rm -f "${pidfile}"
  fi
done
# A new guest disk has a new SSH host key.
rm -f "${HOME}/.config/hello-openshell/known_hosts" \
  "${HOME}/.config/hello-openshell/known_hosts.old"

oc delete vm,vmi,dv,pvc \
  -l app.kubernetes.io/part-of=hello-openshell \
  --ignore-not-found \
  --wait=false \
  || true
oc delete vm,svc minikube-vm rhel-vm hello-openshell-minikube --ignore-not-found --wait=false || true
oc delete dv,pvc minikube-vm-disk rhel-vm-disk hello-openshell-minikube-disk --ignore-not-found --wait=false || true

oc delete all,secret,configmap,route,job \
  -l app.kubernetes.io/part-of=hello-openshell \
  --ignore-not-found
echo "Labeled hello-openshell objects are gone (VMs and Ollama). The Dev Spaces workspace is still running."
