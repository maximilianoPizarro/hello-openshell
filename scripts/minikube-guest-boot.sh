#!/bin/bash
set -euo pipefail
export HOME=/root
export KUBECONFIG=/root/.kube/config
export PATH=/usr/local/bin:$PATH
mkdir -p /var/lib/hello-openshell
grep -q landlock /sys/kernel/security/lsm
echo "fedora ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/fedora-nopasswd
chmod 440 /etc/sudoers.d/fedora-nopasswd
dnf install -y podman conntrack-tools iptables containernetworking-plugins curl tar
curl -fL -o /usr/local/bin/minikube https://github.com/kubernetes/minikube/releases/download/v1.39.0/minikube-linux-amd64
curl -fL -o /usr/local/bin/kubectl https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl
chmod 755 /usr/local/bin/minikube /usr/local/bin/kubectl
curl -fL -o /tmp/helm.tgz https://get.helm.sh/helm-v3.22.1-linux-amd64.tar.gz
tar -xzf /tmp/helm.tgz -C /tmp
install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
systemctl enable --now podman.socket || true
minikube start --driver=podman --container-runtime=containerd --memory=3072 --cpus=2 --disk-size=10g --force
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v1.0.10/sandbox.yaml
kubectl -n agent-sandbox-system rollout status deployment/agent-sandbox-controller --timeout=180s
helm upgrade --install openshell oci://ghcr.io/nvidia/openshell/helm-chart --version 0.1.8 -n openshell --create-namespace
kubectl -n openshell rollout status statefulset/openshell --timeout=300s
install -d -o fedora -g fedora /home/fedora/openshell-client
for k in ca.crt tls.crt tls.key; do
  kubectl -n openshell get secret openshell-client-tls -o go-template="{{index .data \"$k\"}}" | base64 -d > "/home/fedora/openshell-client/$k"
  test -s "/home/fedora/openshell-client/$k"
done
chown fedora:fedora /home/fedora/openshell-client/*
chmod 600 /home/fedora/openshell-client/tls.key
nohup kubectl -n openshell port-forward --address 0.0.0.0 svc/openshell 8080:8080 >/var/log/hello-openshell-gateway.log 2>&1 &
date -Is > /var/lib/hello-openshell/ready
