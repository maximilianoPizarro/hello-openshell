#!/bin/bash
# Same path as make ask / scripts/ask-local.sh: the agent runs inside an
# OpenShell sandbox on the minikube gateway. The sandbox has no network.
# The supervisor dials host.openshell.internal:11434 on the Fedora guest
# (a proxy to CPU Ollama in this project). Usage: curl | python
set -euo pipefail

MODE="${1:-curl}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=sandbox-vm-lib.sh
source "${ROOT}/scripts/sandbox-vm-lib.sh"

MODEL="${SANDBOX_OLLAMA_MODEL:-llama3.2:1b}"
POLICY="${POLICY:-deploy/hi-python.policy.yaml}"
PROFILE="${PROFILE:-deploy/ollama.profile.yaml}"
SANDBOX_IMAGE="${SANDBOX_IMAGE:-registry.access.redhat.com/hi/python:3.12}"
export MSYS_NO_PATHCONV=1
export PATH="${HOME}/.local/bin:${PATH}"

if [[ "$MODE" != "curl" && "$MODE" != "python" ]]; then
  echo "Use: sandbox-ask.sh curl    or    sandbox-ask.sh python"
  exit 1
fi

if [[ "$MODE" == "python" ]]; then
  NAME=hello-agent
  LIST_MODELS=0
  PROMPT='Explica en una frase que es un sandbox y por que un agente deberia correr dentro de uno.'
else
  NAME=hello-ask
  LIST_MODELS=1
  PROMPT='In one sentence, what is a sandbox?'
fi

vm_status="$(oc get vm "${SANDBOX_VM_NAME}" -o jsonpath='{.status.printableStatus}' 2>/dev/null || true)"
if [ "${vm_status}" != "Running" ]; then
  echo "minikube-vm is ${vm_status:-missing}. Run 3. Start minikube VM first."
  echo "The Ask tasks run examples/ask.py inside an OpenShell sandbox on that gateway."
  echo "If rhel-vm is Running, stop it first: quota cannot hold two u1.large VMs plus Ollama."
  exit 1
fi

if [ ! -f "${SANDBOX_VM_KEY}" ]; then
  echo "No SSH key at ${SANDBOX_VM_KEY}. Run 3. Start minikube VM first."
  exit 1
fi

echo "project: ${SANDBOX_VM_NS}"
echo "Ask ${MODE} runs in sandbox ${NAME} on the minikube gateway (host.openshell.internal:11434)."

bash "${ROOT}/scripts/sandbox-ollama-up.sh"
bash "${ROOT}/scripts/install-openshell-cli.sh"
bash "${ROOT}/scripts/sandbox-vm-connect.sh"
sandbox_vm_ensure_ollama_proxy
if ! sandbox_vm_ssh 'python3 -c "import socket; socket.create_connection((\"127.0.0.1\", 11434), 5)"'; then
  echo "Fedora :11434 did not accept connections. The sandbox cannot reach Ollama."
  sandbox_vm_ssh 'sudo -n systemctl status hello-openshell-ollama --no-pager' || true
  exit 1
fi

cd "${ROOT}"
openshell gateway select minikube

if ! openshell profile get ollama >/dev/null 2>&1; then
  openshell profile lint -f "${PROFILE}"
  openshell profile import -f "${PROFILE}"
fi
if ! openshell provider get ollama >/dev/null 2>&1; then
  openshell provider create --name ollama --type ollama
fi

ask_src="$(cat "${ROOT}/examples/ask.py")"
openshell sandbox delete "${NAME}" >/dev/null 2>&1 || true
echo "Creating sandbox ${NAME} from ${SANDBOX_IMAGE}."
openshell sandbox create \
  --name "${NAME}" \
  --from "${SANDBOX_IMAGE}" \
  --provider ollama \
  --policy "${POLICY}" \
  --env OPENAI_BASE_URL=http://host.openshell.internal:11434/v1 \
  --env "MODEL_NAME=${MODEL}" \
  --env OPENAI_API_KEY=fake \
  --env "ASK_PROMPT=${PROMPT}" \
  --env "ASK_LIST_MODELS=${LIST_MODELS}" \
  --no-credential-warnings \
  -- /usr/bin/python3.12 -c "${ask_src}"
openshell sandbox list
