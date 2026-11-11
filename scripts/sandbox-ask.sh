#!/bin/bash
# Call the Developer Sandbox shared Granite predictor.
# The token comes from `oc whoami -t` and is not written to the repo.
# Usage: sandbox-ask.sh curl | sandbox-ask.sh python
set -euo pipefail

MODE="${1:-curl}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CA="${SSL_CERT_FILE:-/var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt}"
BASE="${SANDBOX_MODEL_BASE:-https://isvc-granite-31-8b-fp8-predictor.sandbox-shared-models.svc.cluster.local:8443/v1}"

if [[ ! -f "$CA" ]]; then
  echo "Service CA not found at ${CA}."
  echo "Run this task inside the Dev Spaces workspace on Developer Sandbox."
  exit 1
fi

TOKEN="$(oc whoami -t)"
export SSL_CERT_FILE="$CA"

echo "GET ${BASE}/models"
MODELS="$(curl -fsS --cacert "$CA" -H "Authorization: Bearer ${TOKEN}" "${BASE}/models")"
printf '%s\n' "$MODELS"

MODEL_ID="$(printf '%s' "$MODELS" | python3 -c 'import json,sys; data=json.load(sys.stdin); ids=[item["id"] for item in data.get("data", [])];
prefer=[item for item in ids if "granite" in item.lower()];
print((prefer or ids)[0] if (prefer or ids) else "")')"

if [[ -z "$MODEL_ID" ]]; then
  echo "The predictor returned no model id."
  exit 1
fi

echo "model: ${MODEL_ID}"

if [[ "$MODE" == "curl" ]]; then
  curl -fsS --cacert "$CA" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    "${BASE}/chat/completions" \
    -d "{\"model\":\"${MODEL_ID}\",\"messages\":[{\"role\":\"user\",\"content\":\"In one sentence, what is a sandbox?\"}],\"max_tokens\":80,\"temperature\":0.2}"
  echo
  exit 0
fi

if [[ "$MODE" == "python" ]]; then
  cd "$ROOT"
  export OPENAI_BASE_URL="${BASE}"
  export MODEL_NAME="${MODEL_ID}"
  export RHOAI_API_TOKEN="${TOKEN}"
  python3 examples/ask.py
  exit 0
fi

echo "Use: sandbox-ask.sh curl    or    sandbox-ask.sh python"
exit 1
