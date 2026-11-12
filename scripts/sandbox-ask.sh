#!/bin/bash
# Call Granite/Qwen the same way LiteLLM does in rhdh-agent-sandbox and n8n-sandbox:
# from a pod in this project, to sandbox-shared-models, TLS verify off.
# No LiteMaaS key. In-cluster HTTP has no key; HTTPS 8443 uses the OpenShift
# token from `oc whoami -t` (oauth-proxy), same as those charts.
# Usage: sandbox-ask.sh curl | sandbox-ask.sh python
set -euo pipefail

MODE="${1:-curl}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS="$(oc project -q)"
POD="hello-openshell-ask"

if [[ "$MODE" != "curl" && "$MODE" != "python" ]]; then
  echo "Use: sandbox-ask.sh curl    or    sandbox-ask.sh python"
  exit 1
fi

if [[ "$MODE" == "python" ]]; then
  PROMPT='Explica en una frase que es un sandbox y por que un agente deberia correr dentro de uno.'
else
  PROMPT='In one sentence, what is a sandbox?'
fi

TOKEN="$(oc whoami -t)"
oc delete pod "${POD}" --ignore-not-found --wait=false >/dev/null 2>&1 || true

export MSYS_NO_PATHCONV=1
echo "Asking from a pod in ${NS} (in-cluster DNS, no LiteMaaS key)."

# oc run --env requires KEY=value. The remote script never prints the token.
if ! oc run "${POD}" \
  --image=curlimages/curl:8.11.1 \
  --restart=Never \
  --rm -i \
  --quiet \
  --env="ASK_TOKEN=${TOKEN}" \
  --env="ASK_PROMPT=${PROMPT}" \
  --command -- sh -s <<'REMOTE'
set -eu
bases="
https://isvc-granite-31-8b-fp8-predictor.sandbox-shared-models.svc.cluster.local:8443/v1
http://isvc-granite-31-8b-fp8-predictor.sandbox-shared-models.svc.cluster.local/v1
https://isvc-qwen3-8b-fp8-predictor.sandbox-shared-models.svc.cluster.local:8443/v1
http://isvc-qwen3-8b-fp8-predictor.sandbox-shared-models.svc.cluster.local/v1
"
sa=""
if [ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]; then
  sa="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
fi

try_models() {
  base="$1"
  auth="$2"
  if [ -n "$auth" ]; then
    curl -sk --connect-timeout 5 --max-time 20 -H "Authorization: Bearer ${auth}" "${base}/models"
  else
    curl -sk --connect-timeout 5 --max-time 20 "${base}/models"
  fi
}

ok=""
used=""
auth_used=""
for base in $bases; do
  echo "GET ${base}/models"
  body=""
  for auth in "" "$sa" "$ASK_TOKEN"; do
    if body="$(try_models "$base" "$auth" 2>/dev/null)" && echo "$body" | grep -q '"id"'; then
      ok="$body"
      used="$base"
      auth_used="$auth"
      break
    fi
  done
  if [ -n "$ok" ]; then
    echo "$ok"
    break
  fi
  echo "No answer from ${base}."
done

if [ -z "$ok" ]; then
  echo
  echo "In-cluster DNS did not reach Granite or Qwen."
  echo "That is the same path LiteLLM uses in rhdh-agent-sandbox / n8n-sandbox."
  echo "oc get pods -n sandbox-shared-models is empty on this cluster right now."
  exit 1
fi

model="$(printf '%s' "$ok" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
if [ -z "$model" ]; then
  echo "The predictor returned no model id."
  exit 1
fi
echo "model: ${model}"
echo "base: ${used}"

if [ -n "$auth_used" ]; then
  curl -sk --connect-timeout 15 --max-time 120 \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${auth_used}" \
    "${used}/chat/completions" \
    -d "{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":\"${ASK_PROMPT}\"}],\"max_tokens\":120,\"temperature\":0.2}"
else
  curl -sk --connect-timeout 15 --max-time 120 \
    -H "Content-Type: application/json" \
    "${used}/chat/completions" \
    -d "{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":\"${ASK_PROMPT}\"}],\"max_tokens\":120,\"temperature\":0.2}"
fi
echo
REMOTE
then
  oc delete pod "${POD}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  exit 0
fi
oc delete pod "${POD}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
exit 1
