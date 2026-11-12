#!/bin/bash
# Serve `openshell term` in the Dev Spaces browser. OpenShell 0.1.8 has no
# web console; ttyd wraps the official TUI. The tools container endpoint
# openshell-ui (7681) is a public Route after the workspace starts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TTYD_VERSION="1.7.7"
UI_PORT=7681
DEST="${HOME:-/tmp}/.local/bin"
export PATH="${DEST}:${PATH}"
export TERM="${TERM:-xterm-256color}"
export MSYS_NO_PATHCONV=1

bash "${ROOT}/scripts/install-openshell-cli.sh"

mkdir -p "${DEST}"
case "$(uname -m)" in
  x86_64|amd64) TTYD_ARCH="x86_64" ;;
  aarch64|arm64) TTYD_ARCH="aarch64" ;;
  *)
    echo "No ttyd build for $(uname -m)."
    exit 1
    ;;
esac

if ! command -v ttyd >/dev/null 2>&1; then
  url="https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${TTYD_ARCH}"
  echo "Downloading ${url}"
  curl -fL --retry 3 --retry-delay 2 "$url" -o "${DEST}/ttyd"
  chmod 755 "${DEST}/ttyd"
fi

select_gateway() {
  if openshell gateway select minikube >/dev/null 2>&1; then
    echo "gateway: minikube"
    return 0
  fi
  if openshell gateway select microshift >/dev/null 2>&1; then
    echo "gateway: microshift"
    return 0
  fi
  return 1
}

if oc get vm minikube-vm -o jsonpath='{.status.printableStatus}' 2>/dev/null | grep -qx Running; then
  bash "${ROOT}/scripts/sandbox-vm-connect.sh"
elif oc get vm rhel-vm -o jsonpath='{.status.printableStatus}' 2>/dev/null | grep -qx Running; then
  if [ -f "${ROOT}/scripts/sandbox-rhel-connect.sh" ]; then
    echo "minikube-vm is not Running. Using the RHEL MicroShift gateway if it is already connected."
  fi
fi

if ! select_gateway; then
  echo "No OpenShell gateway is registered. Run 4. Connect minikube gateway, or Connect MicroShift."
  exit 1
fi
openshell status || true

print_urls() {
  echo
  echo "OpenShell UI is the official TUI (openshell term) in the browser."
  echo "Dev Spaces: PORTS → openshell-ui → Open in Browser"
  echo "Routes in this project:"
  oc get route -o custom-columns=NAME:.metadata.name,HOST:.spec.host --no-headers 2>/dev/null \
    | awk 'tolower($0) ~ /openshell-ui|7681/ { print "  https://"$2 }' || true
  if ! oc get route -o name 2>/dev/null | grep -qi 'openshell-ui\|7681'; then
    echo "  (no Route yet: restart the workspace so the openshell-ui endpoint is created)"
  fi
  echo "Leave this task running. Ctrl+C stops the UI."
  echo
}

print_urls

if python3 -c "import socket; socket.create_connection(('127.0.0.1', ${UI_PORT}), 2)" 2>/dev/null; then
  echo "Port ${UI_PORT} is already open. Open the URL above."
  exec sleep infinity
fi

exec ttyd \
  --port "${UI_PORT}" \
  --interface 0.0.0.0 \
  --writable \
  --do-not-check-origin \
  --client-option fontSize=15 \
  --client-option titleFixed=OpenShell \
  env TERM=xterm-256color PATH="${PATH}" openshell term
