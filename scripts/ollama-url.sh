#!/bin/bash
# Print the Ollama base URL for this host. No /v1 suffix.
# Linux and macOS, and Windows with WSL mirrored networking, use localhost.
# Windows with the default WSL NAT mode uses the Podman machine address.
set -euo pipefail

if curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  printf 'http://127.0.0.1:11434\n'
  exit 0
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "127.0.0.1:11434 did not answer, and podman is not on PATH." >&2
  exit 1
fi

# Git Bash rewrites a Unix path in the ssh command unless this is set.
export MSYS_NO_PATHCONV=1
ip="$(podman machine ssh "ip -4 -o addr show scope global" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -v '^127\.' | head -1 || true)"
if [[ -z "${ip}" ]]; then
  echo "127.0.0.1:11434 did not answer, and the Podman machine has no global IPv4 address." >&2
  echo "Start the machine with: podman machine start" >&2
  echo "On Windows, networkingMode=mirrored in %USERPROFILE%\\.wslconfig makes localhost work." >&2
  exit 1
fi
printf 'http://%s:11434\n' "${ip}"
