#!/bin/bash
# Start CPU Ollama (llama3.2:1b) in this project when quota allows.
# GPU is 0 on Developer Sandbox. Does not touch sandbox-shared-models.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="$(oc project -q)"
MODEL="${SANDBOX_OLLAMA_MODEL:-llama3.2:1b}"
LIMIT_MI=4096
export MSYS_NO_PATHCONV=1

to_mi() {
  local v="${1:-0}"
  case "$v" in
    *Gi) echo $(( ${v%Gi} * 1024 )) ;;
    *G) echo $(( ${v%G} * 1024 )) ;;
    *Mi) echo "${v%Mi}" ;;
    *M) echo "${v%M}" ;;
    *) echo 0 ;;
  esac
}

quota_ok() {
  local used hard remain
  used="$(oc get quota compute-deploy -o jsonpath='{.status.used.limits\.memory}' 2>/dev/null || echo 0)"
  hard="$(oc get quota compute-deploy -o jsonpath='{.status.hard.limits\.memory}' 2>/dev/null || echo 0)"
  remain=$(( $(to_mi "$hard") - $(to_mi "$used") ))
  if [ "$remain" -lt "$LIMIT_MI" ]; then
    echo "limits.memory remaining is ${remain}Mi. Ollama ${MODEL} needs a 4Gi limit."
    echo "Stop minikube-vm or rhel-vm (A1. Clean or B1. Clean) and retry. Do not start both VMs plus Ollama."
    return 1
  fi
  echo "quota: limits.memory remaining ${remain}Mi (Ollama limit 4Gi, model ${MODEL})"
}

ollama_pod() {
  oc get pod -l app.kubernetes.io/name=ollama \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

echo "project: ${NS}"
echo "model: ${MODEL} (CPU, no GPU)"

if oc get deploy ollama >/dev/null 2>&1; then
  echo "Deployment ollama already exists."
else
  quota_ok
fi
oc apply -f "${ROOT}/deploy/sandbox-ollama.yaml"

echo "Waiting for Ollama to become ready (image pull can take a few minutes)."
if ! oc rollout status deploy/ollama --timeout=420s; then
  echo "Ollama did not become ready."
  oc get pod -l app.kubernetes.io/name=ollama -o wide || true
  oc describe pod -l app.kubernetes.io/name=ollama | tail -n 40 || true
  exit 1
fi

POD="$(ollama_pod)"
if [ -z "$POD" ]; then
  echo "No Running Ollama pod."
  exit 1
fi
echo "pod: ${POD}"

if oc exec "${POD}" -- ollama list 2>/dev/null | grep -q "${MODEL}"; then
  echo "model ${MODEL} is already on the pod."
else
  echo "Pulling ${MODEL} (~1.3 GiB). First time only; emptyDir is lost if the pod is recreated."
  oc exec "${POD}" -- ollama pull "${MODEL}"
fi

echo "Loading ${MODEL} in the pod. A cold /chat/completions through the sandbox supervisor is closed before the first token."
if ! oc exec "${POD}" -- ollama run "${MODEL}" "hi"; then
  echo "Warmup generate failed. Ask may still hit a closed connection on the first completion."
fi

echo "Ollama: http://ollama.${NS}.svc.cluster.local:11434/v1"
echo "No LiteMaaS key. OPENAI_API_KEY=fake is enough for this API."
