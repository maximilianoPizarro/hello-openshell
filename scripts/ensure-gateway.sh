#!/bin/bash
# Install and register OpenShell 0.1.8 against the Podman socket that
# sees the ollama container. On Linux this runs on the host. On macOS
# and Windows it runs inside `podman machine ssh`.
set -euo pipefail

VERSION="${OPENSHELL_VERSION:-v0.1.8}"
GATEWAY_TOML="${HOME}/.config/openshell/gateway.toml"

detect_socket() {
  if [[ -S /run/podman/podman.sock ]]; then
    printf '/run/podman/podman.sock\n'
    return
  fi
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/podman/podman.sock" ]]; then
    printf '%s\n' "${XDG_RUNTIME_DIR}/podman/podman.sock"
    return
  fi
  if [[ -S "/run/user/$(id -u)/podman/podman.sock" ]]; then
    printf '/run/user/%s/podman/podman.sock\n' "$(id -u)"
    return
  fi
  echo "No Podman socket found. Start Podman or the machine first." >&2
  exit 1
}

pin_socket() {
  local socket="$1"
  mkdir -p "$(dirname "$GATEWAY_TOML")"
  if [[ ! -f "$GATEWAY_TOML" ]]; then
    cat >"$GATEWAY_TOML" <<EOF
[openshell]
version = 2

[openshell.drivers.podman]
compute_driver = "podman"
socket_path = "${socket}"
EOF
    return
  fi
  if grep -q '^socket_path' "$GATEWAY_TOML"; then
    sed -i.bak "s|^socket_path *=.*|socket_path = \"${socket}\"|" "$GATEWAY_TOML"
    rm -f "${GATEWAY_TOML}.bak"
  elif grep -q '^\[openshell\.drivers\.podman\]' "$GATEWAY_TOML"; then
    awk -v s="$socket" '
      BEGIN { done=0 }
      /^\[openshell\.drivers\.podman\]/ { print; print "socket_path = \"" s "\""; done=1; next }
      { print }
    ' "$GATEWAY_TOML" >"${GATEWAY_TOML}.new"
    mv "${GATEWAY_TOML}.new" "$GATEWAY_TOML"
  else
    printf '\n[openshell.drivers.podman]\ncompute_driver = "podman"\nsocket_path = "%s"\n' "$socket" >>"$GATEWAY_TOML"
  fi
}

install_openshell() {
  if command -v openshell >/dev/null 2>&1 && openshell --version 2>/dev/null | grep -q '0.1.8'; then
    echo "openshell 0.1.8 is already installed"
    return
  fi
  curl -LsSf "https://raw.githubusercontent.com/NVIDIA/OpenShell/${VERSION}/install.sh" | \
    OPENSHELL_VERSION="${VERSION}" sh
}

restart_gateway() {
  if systemctl --user is-active openshell-gateway >/dev/null 2>&1 || systemctl --user list-unit-files openshell-gateway.service >/dev/null 2>&1; then
    systemctl --user restart openshell-gateway || true
    return
  fi
  if systemctl is-active openshell-gateway >/dev/null 2>&1; then
    systemctl restart openshell-gateway || true
  fi
}

register_gateway() {
  openshell gateway add https://127.0.0.1:17670 --local --name openshell >/dev/null 2>&1 || true
  openshell gateway select openshell >/dev/null 2>&1 || true
  openshell status
}

run_on_host() {
  install_openshell
  local socket
  socket="$(detect_socket)"
  pin_socket "$socket"
  if command -v openshell-gateway >/dev/null 2>&1; then
    openshell-gateway config preflight --path "$GATEWAY_TOML" || true
  fi
  restart_gateway
  sleep 1
  register_gateway
}

needs_machine() {
  case "$(uname -s)" in
    Darwin) return 0 ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        return 0
      fi
      return 1
      ;;
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

if needs_machine; then
  if ! command -v podman >/dev/null 2>&1; then
    echo "podman is required." >&2
    exit 1
  fi
  export MSYS_NO_PATHCONV=1
  # shellcheck disable=SC2016
  podman machine ssh 'bash -s' <<'EOF'
set -euo pipefail
VERSION="${OPENSHELL_VERSION:-v0.1.8}"
GATEWAY_TOML="${HOME}/.config/openshell/gateway.toml"
detect_socket() {
  if [[ -S /run/podman/podman.sock ]]; then
    printf '/run/podman/podman.sock\n'
    return
  fi
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/podman/podman.sock" ]]; then
    printf '%s\n' "${XDG_RUNTIME_DIR}/podman/podman.sock"
    return
  fi
  if [[ -S "/run/user/$(id -u)/podman/podman.sock" ]]; then
    printf '/run/user/%s/podman/podman.sock\n' "$(id -u)"
    return
  fi
  echo "No Podman socket found inside the machine." >&2
  exit 1
}
if ! command -v openshell >/dev/null 2>&1 || ! openshell --version 2>/dev/null | grep -q '0.1.8'; then
  curl -LsSf "https://raw.githubusercontent.com/NVIDIA/OpenShell/${VERSION}/install.sh" | OPENSHELL_VERSION="${VERSION}" sh
fi
socket="$(detect_socket)"
mkdir -p "$(dirname "$GATEWAY_TOML")"
if [[ ! -f "$GATEWAY_TOML" ]]; then
  cat >"$GATEWAY_TOML" <<TOML
[openshell]
version = 2

[openshell.drivers.podman]
compute_driver = "podman"
socket_path = "${socket}"
TOML
else
  if grep -q '^socket_path' "$GATEWAY_TOML"; then
    sed -i.bak "s|^socket_path *=.*|socket_path = \"${socket}\"|" "$GATEWAY_TOML"
    rm -f "${GATEWAY_TOML}.bak"
  elif grep -q '^\[openshell\.drivers\.podman\]' "$GATEWAY_TOML"; then
    awk -v s="$socket" '
      /^\[openshell\.drivers\.podman\]/ { print; print "socket_path = \"" s "\""; next }
      { print }
    ' "$GATEWAY_TOML" >"${GATEWAY_TOML}.new"
    mv "${GATEWAY_TOML}.new" "$GATEWAY_TOML"
  else
    printf '\n[openshell.drivers.podman]\ncompute_driver = "podman"\nsocket_path = "%s"\n' "$socket" >>"$GATEWAY_TOML"
  fi
fi
if command -v openshell-gateway >/dev/null 2>&1; then
  openshell-gateway config preflight --path "$GATEWAY_TOML" || true
fi
if systemctl --user is-active openshell-gateway >/dev/null 2>&1 || systemctl --user list-unit-files openshell-gateway.service >/dev/null 2>&1; then
  systemctl --user restart openshell-gateway || true
elif systemctl is-active openshell-gateway >/dev/null 2>&1; then
  systemctl restart openshell-gateway || true
fi
sleep 1
openshell gateway add https://127.0.0.1:17670 --local --name openshell >/dev/null 2>&1 || true
openshell gateway select openshell >/dev/null 2>&1 || true
openshell status
EOF
else
  run_on_host
fi
