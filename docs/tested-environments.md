# Environments this guide was written against

This appendix records the stack used while writing the local path. It is not a requirement list. Other Podman versions and hosts work when they provide cgroup v2 and a reachable Ollama API.

| Piece | Value used while writing |
| --- | --- |
| OpenShell | 0.1.8 |
| Compute driver | `podman` |
| cgroup | v2 |
| Ollama | container image `docker.io/ollama/ollama:latest`, model `llama3.2:1b`, 3 GiB / 2 CPUs |
| Sandbox image | `registry.access.redhat.com/hi/python:3.12` (`/usr/bin/python3.12`) |
| Sandbox policy | [deploy/hi-python.policy.yaml](../deploy/hi-python.policy.yaml) (UID/GID `65532`) |
| Host reachability | `127.0.0.1:11434` when available; otherwise the Podman machine global IPv4 |
| Sandbox reachability | `host.openshell.internal:11434` |

Platform notes that affected the scripts:

- On hosts with a Podman machine (macOS, Windows), the gateway installer runs inside the machine.
- On Windows with default WSL NAT, published ports may not answer on `127.0.0.1` from the Windows side. Mirrored networking or the machine IPv4 both work; `scripts/ollama-url.sh` picks whichever answers first.

The Developer Sandbox and OpenShift AI tracks are documented as experimental or admin reference. They were not treated as a verified end-to-end path in the same way as the local Podman flow. On a Developer Sandbox project the stock chart stops before install. With the preflight disabled, the gateway container starts only after `runAsUser` is removed, then exits because `sandboxes.agents.x-k8s.io` is not served.

The documented workaround is OpenShift Virtualization. `minikube-vm` clones the `fedora` DataSource (`u1.large`, 30Gi, `runStrategy: Manual`) and cloud-init installs minikube 1.39.0 with `--driver=podman --container-runtime=containerd --force`. On 11 Nov 2026 a Developer Sandbox project had that API, a Ready `fedora` DataSource, and quota for the instance. The VM reached Running, the disk clone finished, and SSH as `fedora` worked. Cloud-init installed Podman, minikube 1.39.0, kubectl 1.37.0, and Helm 3.22.1, then stopped with `DRV_AS_ROOT` because the Podman driver was started as root without `--force`. The guest script now passes `--force`. Creating an OpenShell sandbox on that minikube was not checked after the flag was added.

Cloud Shell with minikube 1.38.1 was checked on 11 Nov 2026. The Docker runtime (`docker://29.2.1`) rejects the sandbox pod with `SupplementalGroupsPolicyNotSupported`. containerd 2.2.1 on Kubernetes 1.35.1 reports `strict=true` only after `MINIKUBE_FORCE_SYSTEMD=false` and, when runc still demands a systemd cgroup path, `SystemdCgroup = false`. The chart 0.1.8 gateway then stays `Running` and the hardened image pulls. The `agent` container exits 1 because the Cloud Shell kernel lacks `CONFIG_SECURITY_LANDLOCK`. OpenShell 0.1.8 requires Landlock ABI v3.
