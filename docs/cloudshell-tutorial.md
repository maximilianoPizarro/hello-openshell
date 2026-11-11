# OpenShell on GKE

Cloud Shell is the client. The commands below create a GKE Standard cluster in the selected Google Cloud project. The cluster bills until you delete it.

## Create the cluster

Standard, not Autopilot. Ubuntu nodes are the image used for the Landlock check.

```bash
export ZONE="${ZONE:-us-central1-a}"
export CLUSTER="${CLUSTER:-openshell}"
gcloud container clusters create "${CLUSTER}" --zone "${ZONE}" --machine-type e2-standard-2 --num-nodes 2 --image-type UBUNTU_CONTAINERD
gcloud container clusters get-credentials "${CLUSTER}" --zone "${ZONE}"
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

Cloud Shell is Debian. Use the musl binary. Run the port-forward in another terminal, then register the gateway with the `openshell-client-tls` Secret. The steps match the OpenShift module, using `kubectl` instead of `oc`.

```bash
mkdir -p "${HOME}/.local/bin"
curl -fL https://github.com/NVIDIA/OpenShell/releases/download/v0.1.8/openshell-x86_64-unknown-linux-musl.tar.gz | tar -xz -C "${HOME}/.local/bin"
export PATH="${HOME}/.local/bin:${PATH}"
openshell --version
```

## Smoke test

```bash
openshell sandbox create --name model-check --from registry.access.redhat.com/hi/python:3.12 --policy deploy/hi-python.policy.yaml -- /usr/bin/python3.12 -c 'print("ok")'
```

A Landlock or seccomp error means this node kernel cannot run an OpenShell 0.1.8 sandbox.

## Delete the cluster

```bash
gcloud container clusters delete "${CLUSTER}" --zone "${ZONE}"
```
