[![Open in Developer Sandbox](https://img.shields.io/static/v1?label=Open%20in&message=Developer%20Sandbox&logo=eclipseche&color=FDB940&labelColor=525C86)](https://workspaces.openshift.com/#https://github.com/maximilianoPizarro/hello-openshell?storageType=ephemeral)
[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/maximilianoPizarro/hello-openshell&cloudshell_git_branch=main&cloudshell_tutorial=docs/cloudshell-tutorial.md&show=terminal)

<p>
  <a href="https://docs.nvidia.com/openshell/"><img src="docs/assets/logos/nvidia-logo.svg" alt="NVIDIA" height="22"></a>
  &nbsp;
  <a href="https://podman.io/"><img src="docs/assets/logos/podman-logo.png" alt="Podman" height="28"></a>
  &nbsp;
  <a href="https://www.python.org/"><img src="docs/assets/logos/python-logo.svg" alt="Python" height="28"></a>
</p>

# OpenShell with a small model

[examples/ask.py](examples/ask.py) is the same client on four tracks:

| Track | Where it runs | What serves the model |
| --- | --- | --- |
| Local | Podman on Linux, macOS, or Windows | Ollama `llama3.2:1b` (3 GiB cap) |
| Developer Sandbox | Dev Spaces, gateway on an OpenShift Virtualization VM | Shared Granite in `sandbox-shared-models` |
| OpenShift AI | A cluster you administer | Granite 3.3 2B on one NVIDIA GPU |
| Cloud Shell | minikube inside Cloud Shell | Gateway only. This kernel cannot run a sandbox. |

The step-by-step site is in [docs/](docs/index.html) (English and Spanish). The cluster write-up is [docs/openshift-ai.md](docs/openshift-ai.md). What this guide was written against is in [docs/tested-environments.md](docs/tested-environments.md).

![Local architecture](docs/assets/diagrams/local-architecture.jpg)

## Quickstart

From the repository root, with [Podman](https://podman.io/) installed and bash available (native shell, or Git Bash on Windows):

```bash
git clone https://github.com/maximilianoPizarro/hello-openshell
cd hello-openshell
make up
make gateway
make ask
make down
```

| Target | What it does |
| --- | --- |
| `make up` | Starts Ollama from [deploy/compose.yaml](deploy/compose.yaml) and pulls `llama3.2:1b` |
| `make gateway` | Installs OpenShell 0.1.8 against the Podman socket that sees the `ollama` container |
| `make ask` | Creates a sandbox with the hardened Python image and runs `examples/ask.py` |
| `make down` | Deletes `hello-agent` / `model-check` and stops Ollama with its volume |

`scripts/ollama-url.sh` prints the host URL for Ollama (no `/v1` suffix). Use that URL from the host. The sandbox always uses `host.openshell.internal:11434`.

## Platforms

| Platform | Where Podman runs | Host URL for Ollama | Where the gateway runs |
| --- | --- | --- | --- |
| Linux | Native (rootless or rootful) | `http://127.0.0.1:11434` | On the host |
| macOS | `podman machine` | Published port on localhost | Inside the machine |
| Windows | `podman machine` on WSL2 | localhost with mirrored networking, or the machine IPv4 with NAT | Inside the machine |

Shared rules:

- The sandbox has no network of its own. The supervisor dials Ollama as `host.openshell.internal:11434`. Loopback from inside the sandbox is blocked.
- The gateway and `podman ps` must see the same `ollama` container. Pin `socket_path` under `[openshell.drivers.podman]` in `~/.config/openshell/gateway.toml` to that daemon.
- cgroup v2 is required for OpenShell 0.1.8 sandboxes.

### Linux

Install Podman on the host. Start the API socket if your distribution needs it (`systemctl --user enable --now podman.socket` for rootless). `make up` and `make gateway` run on the host. Rootless sockets are usually `/run/user/$(id -u)/podman/podman.sock`. Rootful is `/run/podman/podman.sock`.

### macOS

Create and start a machine (`podman machine init` once, then `podman machine start`). The published port `11434` answers on localhost. There is no Windows-style binary for OpenShell on the Mac host for this guide: `make gateway` installs inside `podman machine ssh`, which is the Linux guest.

### Windows

Install [Podman Desktop](https://podman-desktop.io/) or the Podman CLI so a WSL2 machine exists. There is no native Windows OpenShell binary; the CLI and gateway run inside the machine.

Two ways to reach Ollama from Windows:

1. **Mirrored networking (simpler).** In `%USERPROFILE%\.wslconfig`:

   ```ini
   [wsl2]
   networkingMode=mirrored
   ```

   Restart WSL (`wsl --shutdown`), start the machine again, then `http://127.0.0.1:11434` works from Windows and from Git Bash. `scripts/ollama-url.sh` prefers that address when it answers.

2. **NAT (default).** Windows does not forward the published port to `127.0.0.1`. Use the URL from `make ollama-url` (the machine global IPv4).

Git Bash rewrites Unix paths in some `podman machine ssh` arguments. The scripts set `MSYS_NO_PATHCONV=1` when they need a Unix path. Memory for a WSL machine is set in `.wslconfig`, not with `podman machine set --memory`.

![Where port 11434 is reachable](docs/assets/diagrams/local-windows-net.jpg)

## Versions this guide uses

| Piece | Value |
| --- | --- |
| OpenShell CLI and gateway | 0.1.8 |
| Driver | `podman` |
| Ollama image | `docker.io/ollama/ollama:latest` (3 GiB, 2 CPUs) |
| Model | `llama3.2:1b` |
| Sandbox image | `registry.access.redhat.com/hi/python:3.12` |
| Sandbox policy | [deploy/hi-python.policy.yaml](deploy/hi-python.policy.yaml) |
| Host API | from `scripts/ollama-url.sh` |
| Sandbox API | `http://host.openshell.internal:11434/v1` |

## Step by step

### 1. Start Ollama

```bash
podman compose -f deploy/compose.yaml up -d
OLLAMA_URL="$(bash scripts/ollama-url.sh)"
until curl -fsS "${OLLAMA_URL}/api/tags" >/dev/null; do sleep 2; done
podman exec ollama ollama pull llama3.2:1b
curl -sS "${OLLAMA_URL}/v1/models" -H 'Authorization: Bearer fake'
```

### 2. Install OpenShell

`make gateway` wraps this. Manual path:

**Linux (on the host):**

```bash
curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/v0.1.8/install.sh | \
  OPENSHELL_VERSION=v0.1.8 sh
```

**macOS and Windows (inside the machine):**

```bash
podman machine ssh
# then the same curl | sh installer
```

Under `[openshell.drivers.podman]` in `~/.config/openshell/gateway.toml`, set the socket that lists the `ollama` container:

```toml
socket_path = "/run/podman/podman.sock"
```

On Linux rootless, use `/run/user/$(id -u)/podman/podman.sock` instead.

```bash
openshell-gateway config preflight --path ~/.config/openshell/gateway.toml
systemctl --user restart openshell-gateway
openshell gateway add https://127.0.0.1:17670 --local --name openshell
openshell gateway select openshell
openshell status
openshell --version
```

### 3. Import the profile

[deploy/ollama.profile.yaml](deploy/ollama.profile.yaml) allows only `host.openshell.internal:11434`. It stores no key. Ollama accepts `fake`, and that string opens no other host.

```bash
openshell profile lint -f deploy/ollama.profile.yaml
openshell profile import -f deploy/ollama.profile.yaml
openshell provider create --name ollama --type ollama
openshell provider get ollama
```

### 4. First sandbox

The sandbox image is the [Red Hat Hardened Image for Python 3.12](https://catalog.redhat.com/en/software/containers/hi/python/69c576bbbea7c4011384c57a). The interpreter is `/usr/bin/python3.12`. That image runs as UID `65532`, and the account's primary group in `/etc/passwd` is `0`. OpenShell rejects group `0`, so [deploy/hi-python.policy.yaml](deploy/hi-python.policy.yaml) sets `run_as_user` and `run_as_group` to `65532`.

```bash
export MODEL_NAME=llama3.2:1b

openshell sandbox create \
  --name model-check \
  --from registry.access.redhat.com/hi/python:3.12 \
  --provider ollama \
  --policy deploy/hi-python.policy.yaml \
  -- /usr/bin/python3.12 -c 'import urllib.request; print(urllib.request.urlopen(urllib.request.Request("http://host.openshell.internal:11434/v1/models", headers={"Authorization":"Bearer fake"})).read().decode())'
```

A log line `resolves to always-blocked address` means the URL used `127.0.0.1` or `localhost`.

### 5. Ask with ask.py

[examples/ask.py](examples/ask.py) reads `OPENAI_BASE_URL` and `MODEL_NAME`. It sends `Authorization: Bearer` with `RHOAI_API_TOKEN`, then `OPENAI_API_KEY`, then the literal `fake`.

```bash
openshell sandbox create \
  --name hello-agent \
  --from registry.access.redhat.com/hi/python:3.12 \
  --provider ollama \
  --policy deploy/hi-python.policy.yaml \
  --env OPENAI_BASE_URL=http://host.openshell.internal:11434/v1 \
  --env "MODEL_NAME=${MODEL_NAME}" \
  --env OPENAI_API_KEY=fake \
  -- /usr/bin/python3.12 -c "$(cat examples/ask.py)"
```

`$(cat examples/ask.py)` expands in the shell at the repository root. OpenShell warns that `OPENAI_API_KEY` is visible to the process. Here the value is `fake`. For a real credential, create a provider and attach it with `--provider` instead of `--env`.

![ask.py call](docs/assets/diagrams/local-flow.jpg)

```bash
openshell policy get hello-agent --full
openshell logs hello-agent
podman stats --no-stream ollama
```

## Developer Sandbox (experimental)

Open this repository in [OpenShift Dev Spaces](https://docs.redhat.com/en/documentation/red_hat_openshift_dev_spaces/3.28/html/user_guide/assembly_getting-started_user_guide) on the [Developer Sandbox](https://developers.redhat.com/developer-sandbox) with the button at the top, or paste the repository URL into **Create Workspace**. [devfile.yaml](devfile.yaml) installs the OpenShell 0.1.8 CLI when the workspace starts (`scripts/install-openshell-cli.sh`, the static musl binary, into `~/.local/bin`). A failed install does not stop the workspace. Other tasks wait until you choose them (**Terminal → Run Task…**).

The sandbox project cannot install the gateway. It cannot create CRDs, namespaces, or ClusterRoles, and `agents.x-k8s.io` is not served, so Helm chart 0.1.8 stops if you point it at that API. GPU quota for the user project is typically 0. The workspace still installs the CLI. OpenShift Virtualization in the same project runs `minikube-vm`, a Fedora guest. minikube on that guest uses the Podman driver and containerd, and cloud-init installs Agent Sandbox v1.0.10 plus the chart there. Run the commands in the workspace shell. That shell resolves `minikube-vm.<project>.svc.cluster.local`. A laptop does not.

| Task | Command |
| --- | --- |
| 1. Install OpenShell CLI | `bash scripts/install-openshell-cli.sh` (also on workspace start) |
| 2. Project status | `bash scripts/sandbox-status.sh` |
| 3. Start minikube VM | `bash scripts/sandbox-vm-up.sh` (also runs the connect script) |
| 4. Connect minikube gateway | `bash scripts/sandbox-vm-connect.sh` |
| 5. Create minikube sandbox | `bash scripts/sandbox-vm-sandbox.sh` |
| 6. Ask Granite | `bash scripts/sandbox-ask.sh curl` |
| 7. Ask with ask.py | `bash scripts/sandbox-ask.sh python` |
| 8. Clean | `bash scripts/sandbox-down.sh` |
| 9. Inspect cluster | `bash scripts/sandbox-vm-inspect.sh` |
| Start RHEL terminal | `bash scripts/sandbox-rhel-up.sh` |
| OpenShell terminal | `openshell gateway select minikube && openshell term` |

**OpenShell version** is optional. It repeats the install and runs `openshell --version`. There is no `openshell version` subcommand. **OpenShell terminal** opens the live TUI dashboard (`openshell term`) for gateways, providers, and sandboxes. Run it in the workspace terminal after command 4. There is no web console in OpenShell 0.1.8.

Command 3 applies [deploy/sandbox-minikube-vm.yaml](deploy/sandbox-minikube-vm.yaml). OpenShift Virtualization clones the `fedora` DataSource in `openshift-virtualization-os-images` onto a 30Gi disk. The instance type is `u1.large` (2 vCPU, 8Gi) and `runStrategy` is `Manual`, which is what Developer Sandbox admits. There is no custom image: the sandbox shuts those down. [scripts/sandbox-vm-up.sh](scripts/sandbox-vm-up.sh) starts the VM with the start subresource. Inline cloud-init names `user: fedora` and curls [scripts/minikube-guest-boot.sh](scripts/minikube-guest-boot.sh) at the workspace commit. Admission allows 2048 bytes after the sandbox webhook appends its key. An inline copy of that script was rejected at 1622 bytes. The guest script runs as root, so `minikube start` passes `--force` (`--driver=podman --container-runtime=containerd --memory=3072 --cpus=2 --disk-size=10g`). Without `--force`, minikube 1.39 exits with `DRV_AS_ROOT`. The script also exits if `landlock` is missing from `/sys/kernel/security/lsm`. The containers use that guest kernel. Developer Sandbox stops Linux VMs after one hour. Run command 3 again after that. If the VM object already exists, the script leaves the disk and cloud-init alone, so a changed boot script needs **8. Clean** first. The first successful boot is the one that installs the gateway.

| Piece | Value |
| --- | --- |
| Guest | Fedora DataSource `fedora`, preference `fedora` |
| Instance | `u1.large`, 2 vCPU / 8Gi, disk 30Gi, `runStrategy: Manual` |
| minikube | 1.39.0, Podman driver, containerd, `--force` |
| kubectl / Helm | 1.37.0 / 3.22.1 |
| Gateway | Agent Sandbox v1.0.10, OpenShell chart 0.1.8 |

Command 4 copies the client certificates, opens an SSH tunnel to `127.0.0.1:8080`, and runs `openshell gateway add https://127.0.0.1:8080 --local --name minikube`. It waits up to 40 minutes for `/var/lib/hello-openshell/ready`. If that file never appears, the guest log is `/var/log/cloud-init-output.log`. Command 5 selects that gateway and creates the sandbox inside the VM:

```bash
openshell gateway select minikube
openshell sandbox create \
  --name model-check \
  --from registry.access.redhat.com/hi/python:3.12 \
  --policy deploy/hi-python.policy.yaml \
  -- /usr/bin/python3.12 -c 'print("ok")'
```

OpenShell 0.1.8 needs Landlock ABI v3 on the guest. On 11 Nov 2026 this command printed `ok` and the phase was `Completed`. If a later agent exits, read `openshell logs model-check`. Do not pass OpenShift SCC values into this minikube.

Commands 6 and 7 do not use the VM. They start a short-lived pod in this project and call Granite, then Qwen, the same way LiteLLM does in rhdh-agent-sandbox: `sandbox-shared-models` on port 8443, TLS verify off. There is no LiteMaaS key. HTTP inside the cluster has no Authorization header; HTTPS uses `oc whoami -t` for the oauth-proxy. If CoreDNS has no predictor, the script stops. That does not affect commands 4 and 5. Command 8 deletes `minikube-vm`, `rhel-vm`, and the other objects labeled `app.kubernetes.io/part-of=hello-openshell`.

**Start RHEL terminal** applies [deploy/sandbox-rhel-vm.yaml](deploy/sandbox-rhel-vm.yaml). It is a second guest, `rhel-vm`, cloned from the `rhel9` DataSource with preference `rhel.9`. The user is `cloud-user`. The script writes a password to `~/.config/hello-openshell/rhel.password` and authorizes the same workspace key as the Fedora VM. From the workspace shell:

```bash
ssh -i ~/.config/hello-openshell/minikube_ed25519 -o IdentitiesOnly=yes \
  cloud-user@rhel-vm.$(oc project -q).svc.cluster.local
```

A laptop cannot resolve that name. Forward the service, then use port 2222: `oc port-forward svc/rhel-vm 2222:22`. The OpenShift console login is `cloud-user` plus that password file. This guest does not install minikube: `dnf` on the catalog image needs a subscription. The gateway stays on `minikube-vm`. Both disks are 30Gi and both guests are 8Gi, so stop the Fedora VM before starting this one if the quota is already full. Developer Sandbox still powers it off after one hour. If the VM object already exists, the script leaves the disk and cloud-init alone.

Command 9 prints the same objects from the workspace shell. `oc` sees the VirtualMachine. `openshell` sees `model-check`. `kubectl` for minikube runs inside the guest, over SSH:

```bash
export PATH="${HOME}/.local/bin:${PATH}"
oc get vm,vmi,dv,svc,pod -l app.kubernetes.io/part-of=hello-openshell
openshell gateway select minikube
openshell sandbox list
openshell logs model-check
openshell policy get model-check --full

ssh -i "${HOME}/.config/hello-openshell/minikube_ed25519" \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="${HOME}/.config/hello-openshell/known_hosts" \
  "fedora@minikube-vm.$(oc project -q).svc.cluster.local" \
  'sudo minikube status; sudo kubectl get pods -A; sudo kubectl logs -n openshell openshell-0 --tail=40; sudo kubectl logs -n openshell default--model-check -c agent --tail=40; sudo journalctl -u hello-openshell-gateway -n 20 --no-pager'
```

`openshell-0` is the gateway. `default--model-check` is the sandbox pod. Its containers are `agent` and the init containers `openshell-sandbox-bootstrap` and `workspace-init`. There is no `supervisor` container. The supervisor session is a line in the `openshell-0` log (`ConnectSupervisor`, then `policy status=loaded`, then `ReportMainProcessExit` and `FinalizeMainProcessExit` when the process finishes). A later line `resourceVersion for the provided watch is too old` is an expired Kubernetes watch. The next list still runs. `watched_count=0` means no provider is configured. If the pod name is absent, `kubectl get pods -A` is the list to use. The guest boot log is `sudo tail -n 80 /var/log/cloud-init-output.log` on the same SSH command.

Details: [docs/sandbox/index.html](docs/sandbox/index.html).

## Vanilla Kubernetes from Cloud Shell

[Open in Cloud Shell](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/maximilianoPizarro/hello-openshell&cloudshell_git_branch=main&cloudshell_tutorial=docs/cloudshell-tutorial.md&show=terminal) clones this repository and opens [docs/cloudshell-tutorial.md](docs/cloudshell-tutorial.md). The same steps are on the site at [docs/cloudshell/index.html](docs/cloudshell/index.html) ([español](docs/es/cloudshell/index.html)).

Cloud Shell already includes [minikube](https://minikube.sigs.k8s.io/docs/start/). The cluster runs in that VM, the same pattern as [jitsi-helm](https://github.com/maximilianoPizarro/jitsi-helm). It does not create a GKE cluster and it does not keep a separate bill. You administer it, so you can install the Agent Sandbox CRD. Do not use [deploy/openshift-scc-values.yaml](deploy/openshift-scc-values.yaml) here. That file is for OpenShift `restricted-v2`.

Use containerd. On minikube 1.38.1 the Docker runtime reports `docker://29.2.1` and leaves `supplementalGroupsPolicy` empty. The sandbox pod sets that field to `Strict`, and the kubelet rejects it with `SupplementalGroupsPolicyNotSupported`. Cloud Shell also exports `MINIKUBE_FORCE_SYSTEMD=true`. With that set, containerd 2.2.1 asks runc for a systemd cgroup path while the kubelet, under `cgroups-per-qos=false`, sends `/k8s.io/...`. The control plane never listens. `NodeHasNoDiskPressure` is set while this happens. A disk warning at 95% is not that failure.

```bash
MINIKUBE_FORCE_SYSTEMD=false minikube start --driver=docker --container-runtime=containerd --force-systemd=false
```

If `kubeadm` still waits four minutes and the kubelet log names `slice:prefix:name`, switch containerd to cgroupfs in the running container. The next init attempt can then finish. The node that came up this way was Kubernetes 1.35.1, `containerd://2.2.1`, `strict=true`.

```bash
docker exec minikube sed -i 's/SystemdCgroup = true/SystemdCgroup = false/' /etc/containerd/config.toml
docker exec minikube systemctl restart containerd
docker exec minikube systemctl restart kubelet
kubectl get node minikube -o jsonpath='runtime={.status.nodeInfo.containerRuntimeVersion}{"\n"}strict={.status.features.supplementalGroupsPolicy}{"\n"}'
```

Install the CRD only after that check prints `containerd://2` and `strict=true`.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v1.0.10/sandbox.yaml
kubectl -n agent-sandbox-system rollout status deployment/agent-sandbox-controller --timeout=180s

helm upgrade --install openshell \
  oci://ghcr.io/nvidia/openshell/helm-chart \
  --version 0.1.8 \
  --namespace openshell \
  --create-namespace

kubectl -n openshell rollout status statefulset/openshell --timeout=300s
```

Cloud Shell is Debian. Install the musl CLI, not the Fedora installer. Leave the port-forward running in another terminal. The directory name must match the gateway name. These files are transport credentials.

```bash
mkdir -p "${HOME}/.local/bin"
curl -fL "https://github.com/NVIDIA/OpenShell/releases/download/v0.1.8/openshell-x86_64-unknown-linux-musl.tar.gz" \
  | tar -xz -C "${HOME}/.local/bin"
export PATH="${HOME}/.local/bin:${PATH}"
openshell --version

kubectl -n openshell port-forward svc/openshell 8080:8080
```

```bash
mkdir -p "${HOME}/.config/openshell/gateways/minikube/mtls"
kubectl -n openshell get secret openshell-client-tls -o jsonpath='{.data.ca\.crt}' | base64 -d \
  > "${HOME}/.config/openshell/gateways/minikube/mtls/ca.crt"
kubectl -n openshell get secret openshell-client-tls -o jsonpath='{.data.tls\.crt}' | base64 -d \
  > "${HOME}/.config/openshell/gateways/minikube/mtls/tls.crt"
kubectl -n openshell get secret openshell-client-tls -o jsonpath='{.data.tls\.key}' | base64 -d \
  > "${HOME}/.config/openshell/gateways/minikube/mtls/tls.key"
chmod 600 "${HOME}/.config/openshell/gateways/minikube/mtls/tls.key"
openshell gateway remove minikube
openshell gateway add https://127.0.0.1:8080 --local --name minikube
openshell gateway select minikube
openshell status
```

`openshell gateway remove` prints `No gateway metadata found for 'minikube'` the first time. The `add` on the next line still registers it. `openshell status` then shows `Connected` and `Authenticated (mTLS transport)` for 0.1.8.

The hardened image does pull (`registry.access.redhat.com/hi/python:3.12`, about 39 MB). The `agent` container then exits 1 in the same second. `kubectl logs -n openshell default--model-check -c agent` prints `Landlock ABI v3 or newer (Linux 6.2+) is required, but Landlock is not implemented (kernel lacks CONFIG_SECURITY_LANDLOCK)`. Minikube's docker driver uses the Cloud Shell kernel, and that kernel does not implement Landlock. The supervisor process starts, and its readiness probe to port 5501 stays refused because the agent is already dead. `openshell-0` stays `Running`. A sandbox needs a kernel with Landlock ABI v3. The command below is the check.

```bash
openshell sandbox create \
  --name model-check \
  --from registry.access.redhat.com/hi/python:3.12 \
  --policy deploy/hi-python.policy.yaml \
  -- /usr/bin/python3.12 -c 'print("ok")'
```

Delete the minikube cluster when you are done.

```bash
minikube delete
```

## OpenShift AI (admin reference)

The admin path (OpenShift 4.19+, Agent Sandbox v1.0.10, Helm chart 0.1.8, vLLM chart 0.7.1, Granite 3.3 2B) is [docs/openshift-ai.md](docs/openshift-ai.md), with [deploy/granite-2b-values.yaml](deploy/granite-2b-values.yaml) and [deploy/rhoai-granite.profile.yaml](deploy/rhoai-granite.profile.yaml). Treat it as a reference until you apply it on a cluster you administer.

![OpenShift path](docs/assets/diagrams/openshift-architecture.jpg)

## When something fails

| Category | What you see | Where to look |
| --- | --- | --- |
| Platform | `podman` cannot connect | `podman machine start` on macOS/Windows. On Linux, start the Podman socket. |
| Memory | The Ollama container is killed | `podman stats ollama`. Raise `mem_limit` in [deploy/compose.yaml](deploy/compose.yaml) to `4g`. Stay on `llama3.2:1b` when RAM is tight. |
| Model | `/v1/models` has no `llama3.2:1b` | `podman exec ollama ollama pull llama3.2:1b` is still running. `podman logs ollama`. |
| Network (Windows NAT) | `curl` to `127.0.0.1:11434` from Windows returns connection refused | Use `make ollama-url`, or switch WSL to `networkingMode=mirrored`. |
| Gateway | The gateway creates no containers | `socket_path` must be the daemon that lists `ollama`. |
| Image | Sandbox exits naming Landlock or seccomp | The kernel refused the filter. OpenShell 0.1.8 needs that check. On the VM path the kernel is the Fedora guest, not the Dev Spaces node. |
| VM | Guest log says `DRV_AS_ROOT` | minikube 1.39 refuses the Podman driver as root unless `--force` is set. Clean the VM so cloud-init runs the current guest script. |
| VM | SSH to the guest says `Permission denied` | Cloud-init kept the key from the first boot. Run 8. Clean, then 3. Start minikube VM. |
| Policy | `no matching policy` names a binary | On the hardened image the interpreter is `/usr/bin/python3.12`. Update the profile and keep `resource_version`. |
| Policy | `configure an explicit workload group` | The image user `65532` has primary group `0`. Pass `--policy deploy/hi-python.policy.yaml`. |
| Policy | `resolves to always-blocked address` | The sandbox URL used loopback. Use `host.openshell.internal`. |

To update a profile that is already imported:

```bash
openshell profile export ollama -o yaml > /tmp/ollama.profile.yaml
# edit binaries, keep resource_version
openshell profile update ollama -f /tmp/ollama.profile.yaml
```

## Tear down

```bash
make down
```

Or by hand:

```bash
openshell sandbox delete hello-agent model-check
openshell provider delete ollama
openshell profile delete ollama
podman compose -f deploy/compose.yaml down -v
```

With this compose file the volume name is `deploy_ollama`. On Windows or macOS, `podman machine stop` releases the machine RAM when you are done.

## Pages

The site in [docs/](docs/index.html) is plain HTML. [.github/workflows/gh-pages.yml](.github/workflows/gh-pages.yml) publishes that folder on push to `main` or `master`.

## License

This repository is licensed under the [Apache License 2.0](LICENSE).

## References

- [OpenShell installation](https://docs.nvidia.com/openshell/latest/about/installation) and [sandbox runtimes](https://docs.nvidia.com/openshell/latest/how-it-works/sandboxes/runtimes)
- [Inference](https://docs.nvidia.com/openshell/how-it-works/inference)
- [Ollama OpenAI API](https://github.com/ollama/ollama/blob/main/docs/openai.md)
- [Podman](https://podman.io/) and [podman machine](https://docs.podman.io/en/latest/markdown/podman-machine.1.html)
- [Python](https://www.python.org/)
- [Red Hat Hardened Images](https://catalog.redhat.com/en/software/containers/hi/python/69c576bbbea7c4011384c57a)
- [OpenShift AI module](docs/openshift-ai.md)

## Trademarks

NVIDIA and OpenShell are trademarks of NVIDIA Corporation. This is an independent guide. The wordmark in `docs/assets/logos/nvidia-logo.svg` names the product and is not covered by the Apache-2.0 license. It does not imply endorsement.

The Podman logo in `docs/assets/logos/podman-logo.png` is the project logo from [podman-container-tools/podman](https://github.com/podman-container-tools/podman/tree/main/logo). Podman is a trademark of Red Hat, Inc.

The Python logo in `docs/assets/logos/python-logo.svg` is the official logo from [python.org/community/logos](https://www.python.org/community/logos/). Python and the Python logo are trademarks of the Python Software Foundation. Use here names the sandbox image. It does not imply PSF endorsement.

Red Hat, OpenShift, and OpenShift Dev Spaces are trademarks of Red Hat, Inc. Those logo files are not included.
