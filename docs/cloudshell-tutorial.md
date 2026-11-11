# OpenShell on minikube

Cloud Shell is the client. `minikube start` creates a Kubernetes cluster inside that VM. It does not create a GKE cluster.

## Start minikube

Cloud Shell already includes minikube. Use containerd, and do not force systemd. The Docker runtime cannot admit `supplementalGroupsPolicy: Strict`.

```bash
MINIKUBE_FORCE_SYSTEMD=false minikube start --driver=docker --container-runtime=containerd --force-systemd=false
```

If kubeadm is still waiting after four minutes and the kubelet log names `slice:prefix:name`, containerd is still on systemd cgroups. Switch it, then let the next init attempt finish. Continue only when the node prints `containerd://2` and `strict=true`. The Docker runtime (`docker://29.2.1`) rejects the sandbox with `SupplementalGroupsPolicyNotSupported`.

```bash
docker exec minikube sed -i 's/SystemdCgroup = true/SystemdCgroup = false/' /etc/containerd/config.toml
docker exec minikube systemctl restart containerd
docker exec minikube systemctl restart kubelet
kubectl get node minikube -o jsonpath='runtime={.status.nodeInfo.containerRuntimeVersion}{"\n"}strict={.status.features.supplementalGroupsPolicy}{"\n"}'
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
openshell gateway remove minikube
openshell gateway add https://127.0.0.1:8080 --local --name minikube
openshell gateway select minikube
openshell status
```

The first `gateway remove` prints `No gateway metadata found for 'minikube'`. The following `add` still registers the certificates. `openshell status` then shows `Connected`.

## Smoke test

```bash
openshell sandbox create --name model-check --from registry.access.redhat.com/hi/python:3.12 --policy deploy/hi-python.policy.yaml -- /usr/bin/python3.12 -c 'print("ok")'
kubectl logs -n openshell default--model-check -c agent
```

The image pulls. The agent container exits 1 in the same second. The log says Landlock ABI v3 is required and `CONFIG_SECURITY_LANDLOCK` is missing. The supervisor starts, and its readiness probe to port 5501 stays refused. `openshell-0` stays Running. OpenShell 0.1.8 needs a kernel with Landlock ABI v3. The Cloud Shell kernel is not that kernel.

## Delete the cluster

```bash
minikube delete
```
