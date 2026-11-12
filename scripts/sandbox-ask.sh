#!/bin/bash
# Same path as make ask / scripts/ask-local.sh: the agent runs inside an
# OpenShell sandbox on the minikube or MicroShift gateway. The sandbox has
# no network. The supervisor dials host.openshell.internal:11434 on the guest
# (a proxy to CPU Ollama in this project). Usage: curl | python | turns
# SANDBOX_GATEWAY=minikube|microshift (default minikube).
set -euo pipefail

MODE="${1:-curl}"
SANDBOX_GATEWAY="${SANDBOX_GATEWAY:-minikube}"
export SANDBOX_GATEWAY
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=sandbox-vm-lib.sh
source "${ROOT}/scripts/sandbox-vm-lib.sh"

MODEL="${SANDBOX_OLLAMA_MODEL:-llama3.2:1b}"
POLICY="${POLICY:-deploy/hi-python.policy.yaml}"
SANDBOX_IMAGE="${SANDBOX_IMAGE:-registry.access.redhat.com/hi/python:3.12}"
export MSYS_NO_PATHCONV=1
export PATH="${HOME}/.local/bin:${PATH}"

if [[ "$MODE" != "curl" && "$MODE" != "python" && "$MODE" != "turns" ]]; then
  echo "Use: sandbox-ask.sh curl | python | turns"
  exit 1
fi

if [[ "${SANDBOX_GATEWAY}" != "minikube" && "${SANDBOX_GATEWAY}" != "microshift" ]]; then
  echo "SANDBOX_GATEWAY must be minikube or microshift."
  exit 1
fi

ASK_PY="${ROOT}/examples/ask.py"
FOLLOWUP=""
if [[ "$MODE" == "python" ]]; then
  NAME=hello-agent
  LIST_MODELS=0
  PROMPT='Explica en una frase que es un sandbox y por que un agente deberia correr dentro de uno.'
elif [[ "$MODE" == "turns" ]]; then
  NAME=hello-turns
  LIST_MODELS=0
  PROMPT='Explica en una frase que es un sandbox y por que un agente deberia correr dentro de uno.'
  FOLLOWUP='En una frase, por que ese agente no deberia tener red propia?'
  ASK_PY="${ROOT}/examples/ask_turns.py"
else
  NAME=hello-ask
  LIST_MODELS=1
  PROMPT='In one sentence, what is a sandbox?'
fi

vm_name="$(sandbox_gateway_vm)"
vm_status="$(oc get vm "${vm_name}" -o jsonpath='{.status.printableStatus}' 2>/dev/null || true)"
if [ "${vm_status}" != "Running" ]; then
  other_vm="$(sandbox_gateway_other_vm)"
  other_status="$(oc get vm "${other_vm}" -o jsonpath='{.status.printableStatus}' 2>/dev/null || true)"
  echo "${vm_name} is ${vm_status:-missing}."
  echo "The Ask tasks run examples/ask.py inside an OpenShell sandbox on that gateway."
  if [ "${other_status}" = "Running" ]; then
    echo "${other_vm} is Running. Quota cannot hold two u1.large VMs plus Ollama."
    echo "Run $(sandbox_gateway_clean_task), then $(sandbox_gateway_start_task)."
  elif [ -z "${vm_status}" ]; then
    echo "The VM object is gone. Run $(sandbox_gateway_start_task). Do not Clean: that also deletes Ollama."
  else
    echo "Run $(sandbox_gateway_start_task) to start it. Developer Sandbox stops Linux VMs after one hour."
  fi
  exit 1
fi

if [ ! -f "${SANDBOX_VM_KEY}" ]; then
  echo "No SSH key at ${SANDBOX_VM_KEY}. Run $(sandbox_gateway_start_hint) first."
  exit 1
fi

echo "project: ${SANDBOX_VM_NS}"
echo "Ask ${MODE} runs in sandbox ${NAME} on the ${SANDBOX_GATEWAY} gateway (host.openshell.internal:11434)."

bash "${ROOT}/scripts/install-openshell-cli.sh"
sandbox_finish_ollama "${ROOT}"
if sandbox_openshell_gateway_connected "${SANDBOX_GATEWAY}"; then
  echo "Gateway ${SANDBOX_GATEWAY} already connected. Skipping gateway re-add."
  sandbox_openshell_prepare_ask "${ROOT}"
else
  if [ "${SANDBOX_GATEWAY}" = "microshift" ]; then
    bash "${ROOT}/scripts/sandbox-rhel-connect.sh"
  else
    bash "${ROOT}/scripts/sandbox-vm-connect.sh"
  fi
fi

cd "${ROOT}"
openshell gateway select "${SANDBOX_GATEWAY}"
host_ip="$(sandbox_guest_host_gateway_ip || true)"

ask_src="$(cat "${ASK_PY}")"
openshell sandbox delete "${NAME}" >/dev/null 2>&1 || true
echo "Creating sandbox ${NAME} from ${SANDBOX_IMAGE}."
create_args=(
  --name "${NAME}"
  --from "${SANDBOX_IMAGE}"
  --provider ollama
  --policy "${POLICY}"
  --env OPENAI_BASE_URL=http://host.openshell.internal:11434/v1
  --env "MODEL_NAME=${MODEL}"
  --env OPENAI_API_KEY=fake
  --env "ASK_PROMPT=${PROMPT}"
  --env "ASK_LIST_MODELS=${LIST_MODELS}"
  --env "ASK_HOST_IP=${host_ip}"
)
if [ -n "${FOLLOWUP}" ]; then
  create_args+=(--env "ASK_FOLLOWUP=${FOLLOWUP}")
fi
openshell sandbox create \
  "${create_args[@]}" \
  --no-credential-warnings \
  -- /usr/bin/python3.12 -c "${ask_src}"
openshell sandbox list
