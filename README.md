[![Open in Developer Sandbox](https://img.shields.io/static/v1?label=Open%20in&message=Developer%20Sandbox&logo=eclipseche&color=FDB940&labelColor=525C86)](https://workspaces.openshift.com/#https://github.com/maximilianoPizarro/hello-openshell?storageType=ephemeral)

<p>
  <a href="https://docs.nvidia.com/openshell/">NVIDIA OpenShell</a>
  &nbsp;
  <a href="https://podman.io/"><img src="docs/assets/logos/podman-logo.png" alt="Podman" height="28"></a>
  &nbsp;
  <a href="https://www.python.org/"><img src="docs/assets/logos/python-logo.svg" alt="Python" height="28"></a>
</p>

# OpenShell with a small model

[examples/ask.py](examples/ask.py) is the same client on three tracks:

| Track | Where it runs | What serves the model |
| --- | --- | --- |
| Local | Podman on Linux, macOS, or Windows | Ollama `llama3.2:1b` (3 GiB cap) |
| Developer Sandbox | OpenShift Dev Spaces | An OpenAI-compatible predictor you can reach from the workspace |
| OpenShift AI | A cluster you administer | Granite 3.3 2B on one NVIDIA GPU |

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

This track does not install the gateway. A Developer Sandbox project cannot create CRDs, namespaces, or ClusterRoles, and `agents.x-k8s.io` is not served, so Helm chart 0.1.8 stops. GPU quota for the user project is typically 0. After the CLI install, check with `openshell --version`. `openshell status` needs a gateway.

| Task | What it runs |
| --- | --- |
| Install OpenShell CLI | `scripts/install-openshell-cli.sh` (also on workspace start) |
| OpenShell version | the same install, then `openshell --version` |
| Project status | `scripts/sandbox-status.sh` |
| Ask Granite | `scripts/sandbox-ask.sh curl` (needs `SANDBOX_MODEL_BASE`) |
| Ask with ask.py | `scripts/sandbox-ask.sh python` (needs `SANDBOX_MODEL_BASE`) |
| Clean | deletes objects labeled `app.kubernetes.io/part-of=hello-openshell` |

There is no fixed shared-model hostname. Set `SANDBOX_MODEL_BASE` to an OpenAI-compatible `/v1` URL the workspace can resolve before running the Ask tasks.

Details: [docs/sandbox/index.html](docs/sandbox/index.html).

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
| Image | Sandbox exits naming Landlock or seccomp | The kernel refused the filter. OpenShell 0.1.8 needs that check. |
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

NVIDIA and OpenShell are trademarks of NVIDIA Corporation. This is an independent guide. The NVIDIA logo file is not included; the name links to the product documentation.

The Podman logo in `docs/assets/logos/podman-logo.png` is the project logo from [podman-container-tools/podman](https://github.com/podman-container-tools/podman/tree/main/logo). Podman is a trademark of Red Hat, Inc.

The Python logo in `docs/assets/logos/python-logo.svg` is the official logo from [python.org/community/logos](https://www.python.org/community/logos/). Python and the Python logo are trademarks of the Python Software Foundation. Use here names the sandbox image. It does not imply PSF endorsement.

Red Hat, OpenShift, and OpenShift Dev Spaces are trademarks of Red Hat, Inc. Those logo files are not included.
