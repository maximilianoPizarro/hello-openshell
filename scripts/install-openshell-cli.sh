#!/bin/bash
# Install the OpenShell 0.1.8 CLI into the Dev Spaces workspace.
# The static musl binary runs on the universal developer image.
# This does not install the gateway. Developer Sandbox cannot serve
# agents.x-k8s.io, which the Helm chart requires.
set -euo pipefail

VERSION="v0.1.8"
ASSET_VERSION="0.1.8"

case "$(uname -m)" in
  x86_64|amd64) ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
  *)
    echo "No OpenShell musl build for $(uname -m)."
    exit 1
    ;;
esac

if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  DEST="/usr/local/bin"
  install_bin() { sudo install -m 0755 "$1" "${DEST}/openshell"; }
else
  DEST="${HOME}/.local/bin"
  mkdir -p "$DEST"
  install_bin() { install -m 0755 "$1" "${DEST}/openshell"; }
  case ":${PATH}:" in
    *":${DEST}:"*) ;;
    *)
      printf '\nexport PATH="%s:${PATH}"\n' "$DEST" >> "${HOME}/.bashrc"
      export PATH="${DEST}:${PATH}"
      ;;
  esac
fi

if "${DEST}/openshell" version 2>/dev/null | grep -q "${ASSET_VERSION}"; then
  echo "openshell ${ASSET_VERSION} is already in ${DEST}"
  "${DEST}/openshell" version
  exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
url="https://github.com/NVIDIA/OpenShell/releases/download/${VERSION}/openshell-${ARCH}-unknown-linux-musl.tar.gz"
echo "Downloading ${url}"
curl -fsSL "$url" -o "${tmpdir}/openshell.tgz"
tar -xzf "${tmpdir}/openshell.tgz" -C "$tmpdir"
install_bin "${tmpdir}/openshell"
echo "Installed ${DEST}/openshell"
"${DEST}/openshell" version
