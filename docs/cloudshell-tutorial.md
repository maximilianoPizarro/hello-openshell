# OpenShell on minikube

Cloud Shell is the client. `minikube start` creates a Kubernetes cluster inside that VM. It does not create a GKE cluster.

## Start minikube

Cloud Shell already includes minikube. The docker driver is the one that starts there.

```bash
minikube start --driver=docker
```

## Install Agent Sandbox

OpenShell does not install this CRD. You can apply it because you administer this cluster.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v1.0.10/sandbox.yaml
kubectl -n agent-sandbox-system rollout status deployment/agent-sandbox-controller --timeout=180s
```

## Install the gateway

Do not pass the OpenShift SCC values. Those are for `restricted-v2` only.

```bash
helm upgrade --install openshell oci://ghcr.io/nvidia/openshell/helm-chart --version 0.1.8 --namespace openshell --create-namespace
kubectl -n openshell rollout status statefulset/openshell --timeout=300s
```

If `helm` is missing:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## Connect the CLI

Cloud Shell is Debian. Use the musl binary. Leave the port-forward running in another terminal. The directory name must match the gateway name.

```bash
mkdir -p "${HOME}/.local/bin"
curl -fL https://github.com/NVIDIA/OpenShell/releases/download/v0.1.8/openshell-x86_64-unknown-linux-musl.tar.gz | tar -xz -C "${HOME}/.local/bin"
export PATH="${HOME}/.local/bin:${PATH}"
openshell --version
```

```bash
kubectl -n openshell port-forward svc/openshell 8080:8080
```

```bash
mkdir -p "${HOME}/.config/openshell/gateways/minikube/mtls"
kubectl -n openshell get secret openshell-client-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > "${HOME}/.config/openshell/gateways/minikube/mtls/ca.crt"
kubectl -n openshell get secret openshell-client-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > "${HOME}/.config/openshell/gateways/minikube/mtls/tls.crt"
kubectl -n openshell get secret openshell-client-tls -o jsonpath='{.data.tls\.key}' | base64 -d > "${HOME}/.config/openshell/gateways/minikube/mtls/tls.key"
chmod 600 "${HOME}/.config/openshell/gateways/minikube/mtls/tls.key"
openshell gateway add https://127.0.0.1:8080 --local --name minikube
openshell gateway select minikube
openshell status
```

## Smoke test

```bash
openshell sandbox create --name model-check --from registry.access.redhat.com/hi/python:3.12 --policy deploy/hi-python.policy.yaml -- /usr/bin/python3.12 -c 'print("ok")'
```

A Landlock or seccomp error means this node kernel cannot run an OpenShell 0.1.8 sandbox. With the docker driver, that kernel is the Cloud Shell VM.

## Delete the cluster

```bash
minikube delete
```
