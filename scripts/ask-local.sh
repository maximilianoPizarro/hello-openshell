#!/bin/bash
# Create a hardened-image sandbox and run examples/ask.py against Ollama.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODEL_NAME="${MODEL_NAME:-llama3.2:1b}"
SANDBOX_IMAGE="${SANDBOX_IMAGE:-registry.access.redhat.com/hi/python:3.12}"
POLICY="${POLICY:-deploy/hi-python.policy.yaml}"
PROFILE="${PROFILE:-deploy/ollama.profile.yaml}"

host_to_machine_path() {
  local p="$1"
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      p="$(cygpath -u "$p" 2>/dev/null || printf '%s' "$p")"
      if [[ "$p" =~ ^/([a-zA-Z])/(.*) ]]; then
        printf '/mnt/%s/%s\n' "$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')" "${BASH_REMATCH[2]}"
        return
      fi
      ;;
  esac
  printf '%s\n' "$p"
}

ensure_profile() {
  if openshell_cmd profile get ollama >/dev/null 2>&1; then
    return
  fi
  openshell_cmd profile lint -f "$1/$PROFILE"
  openshell_cmd profile import -f "$1/$PROFILE"
}

ensure_provider() {
  if openshell_cmd provider get ollama >/dev/null 2>&1; then
    return
  fi
  openshell_cmd provider create --name ollama --type ollama
}

run_ask() {
  local repo="$1"
  ensure_profile "$repo"
  ensure_provider
  # Expand on the host that has the file, then pass the source as -c.
  local ask_src
  ask_src="$(cat "${repo}/examples/ask.py")"
  openshell_cmd sandbox create \
    --name hello-agent \
    --from "$SANDBOX_IMAGE" \
    --provider ollama \
    --policy "${repo}/${POLICY}" \
    --env OPENAI_BASE_URL=http://host.openshell.internal:11434/v1 \
    --env "MODEL_NAME=${MODEL_NAME}" \
    --env OPENAI_API_KEY=fake \
    --no-credential-warnings \
    -- /usr/bin/python3.12 -c "${ask_src}"
}

if command -v openshell >/dev/null 2>&1; then
  openshell_cmd() { openshell "$@"; }
  run_ask "$ROOT"
  exit 0
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "openshell is not on PATH and podman is missing." >&2
  exit 1
fi

export MSYS_NO_PATHCONV=1
REPO_IN_VM="$(host_to_machine_path "$ROOT")"
# Confirm the mount is visible inside the machine.
if ! podman machine ssh -- test -f "${REPO_IN_VM}/examples/ask.py"; then
  echo "The repository is not visible inside the Podman machine at ${REPO_IN_VM}." >&2
  echo "Clone or copy the repo into a path the machine mounts, then retry." >&2
  exit 1
fi

# Run the same logic inside the machine, where the gateway CLI lives.
# shellcheck disable=SC2016
podman machine ssh -- bash -lc "set -euo pipefail
MODEL_NAME='${MODEL_NAME}'
SANDBOX_IMAGE='${SANDBOX_IMAGE}'
POLICY='${POLICY}'
PROFILE='${PROFILE}'
ROOT='${REPO_IN_VM}'
cd \"\$ROOT\"
if ! openshell profile get ollama >/dev/null 2>&1; then
  openshell profile lint -f \"\$ROOT/\$PROFILE\"
  openshell profile import -f \"\$ROOT/\$PROFILE\"
fi
if ! openshell provider get ollama >/dev/null 2>&1; then
  openshell provider create --name ollama --type ollama
fi
ASK_SRC=\"\$(cat examples/ask.py)\"
openshell sandbox create \\
  --name hello-agent \\
  --from \"\$SANDBOX_IMAGE\" \\
  --provider ollama \\
  --policy \"\$ROOT/\$POLICY\" \\
  --env OPENAI_BASE_URL=http://host.openshell.internal:11434/v1 \\
  --env \"MODEL_NAME=\${MODEL_NAME}\" \\
  --env OPENAI_API_KEY=fake \\
  --no-credential-warnings \\
  -- /usr/bin/python3.12 -c \"\$ASK_SRC\"
"
