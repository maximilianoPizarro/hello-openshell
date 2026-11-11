#!/bin/bash
# Create the Fedora minikube VM from a Dev Spaces workspace, or from a shell
# that is already logged in to the sandbox project.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=sandbox-vm-lib.sh
source "${ROOT}/scripts/sandbox-vm-lib.sh"

if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "ssh-keygen is not installed in this shell."
  exit 1
fi

mkdir -p "${SANDBOX_VM_CFG}"
chmod 700 "${SANDBOX_VM_CFG}"
if [ ! -f "${SANDBOX_VM_KEY}" ]; then
  ssh-keygen -t ed25519 -N "" -f "${SANDBOX_VM_KEY}" -C "hello-openshell-devspaces"
fi
chmod 600 "${SANDBOX_VM_KEY}"

echo "user: $(oc whoami)"
echo "project: ${SANDBOX_VM_NS}"
echo
echo "=== quota ==="
oc get quota
echo
if ! oc get datasource fedora -n openshift-virtualization-os-images >/dev/null 2>&1; then
  echo "The fedora DataSource is not readable in openshift-virtualization-os-images."
  echo "The VM manifest still references it. If create fails, the boot source is missing."
fi

if oc get vm "${SANDBOX_VM_NAME}" >/dev/null 2>&1; then
  echo "VM ${SANDBOX_VM_NAME} already exists. Leaving its disk and cloud-init alone."
else
  pass_file="${SANDBOX_VM_CFG}/fedora.password"
  if [ ! -f "${pass_file}" ]; then
    openssl rand -hex 12 > "${pass_file}"
    chmod 600 "${pass_file}"
  fi
  rendered="$(mktemp)"
  secret_yaml="$(mktemp)"
  trap 'rm -f "${rendered}" "${secret_yaml}"' EXIT
  if command -v python3 >/dev/null 2>&1; then
    py=python3
  else
    py=python
  fi
  REV="$(git -C "${ROOT}" rev-parse HEAD)"
  echo "guest boot script commit: ${REV}"
  ROOT="${ROOT}" PUB="$(cat "${SANDBOX_VM_KEY}.pub")" PASS="$(cat "${pass_file}")" OUT="${rendered}" REV="${REV}" \
    "${py}" - <<'PY'
import os
from pathlib import Path

root = Path(os.environ["ROOT"])
url = (
    "https://raw.githubusercontent.com/maximilianoPizarro/hello-openshell/"
    + os.environ["REV"]
    + "/scripts/minikube-guest-boot.sh"
)
# No single quotes: this string is one single-quoted cloud-init runcmd.
command = (
    "i=0; u=%s; while [ $i -lt 12 ]; do curl -fsSL -o /usr/local/sbin/minikube-vm.sh $u && break; i=$((i+1)); sleep 5; done; test -s /usr/local/sbin/minikube-vm.sh && bash /usr/local/sbin/minikube-vm.sh"
    % url
)
user_data = """#cloud-config
user: fedora
password: {password}
chpasswd:
  expire: false
ssh_pwauth: true
ssh_authorized_keys:
  - {pubkey}
runcmd:
  - '{command}'
""".format(
    password=os.environ["PASS"].strip(),
    pubkey=os.environ["PUB"].strip(),
    command=command,
)
size = len(user_data.encode("utf-8"))
# Admission allows 2048 bytes after the sandbox webhook appends its SSH key.
# An inline copy of the boot script was 1622 bytes and was rejected.
if size > 1400:
    raise SystemExit("cloud-init userData is %s bytes. Keep it under 1400 so the sandbox can add a key." % size)
print("cloud-init userData bytes:", size)
text = (root / "deploy" / "sandbox-minikube-vm.yaml").read_text(encoding="utf-8").replace("\r\n", "\n")
lines = text.split("\n")
found = False
for index, line in enumerate(lines):
    if line.strip() != "__CLOUD_INIT__":
        continue
    pad = line[: len(line) - len(line.lstrip(" "))]
    lines[index] = "\n".join((pad + item) if item else "" for item in user_data.split("\n"))
    found = True
    break
if not found:
    raise SystemExit("deploy/sandbox-minikube-vm.yaml is missing __CLOUD_INIT__")
rendered = "\n".join(lines) + "\n"
if any(line.strip() == "__CLOUD_INIT__" for line in rendered.split("\n")):
    raise SystemExit("cloud-init placeholder survived rendering")
# write_bytes keeps LF on Python 3.9. Path.write_text(newline=) needs 3.10.
Path(os.environ["OUT"]).write_bytes(rendered.encode("utf-8"))
PY
  oc delete secret minikube-vm-cloudinit hello-openshell-minikube-cloudinit --ignore-not-found
  apply_path="${rendered}"
  if command -v cygpath >/dev/null 2>&1; then
    apply_path="$(cygpath -w "${rendered}")"
  fi
  echo "applying ${apply_path}"
  MSYS_NO_PATHCONV=1 oc apply -f "${apply_path}"
  echo "VM ${SANDBOX_VM_NAME} created."
  echo "Console password file: ${pass_file}"
fi

status="$(oc get vm "${SANDBOX_VM_NAME}" -o jsonpath='{.status.printableStatus}')"
if [ "${status}" != "Running" ]; then
  server="$(oc whoami --show-server)"
  start_code="$(curl -sS -o "${SANDBOX_VM_CFG}/start.json" -w "%{http_code}" -k -X PUT \
    -H "Authorization: Bearer $(oc whoami -t)" \
    -H "Content-Type: application/json" \
    -d '{}' \
    "${server}/apis/subresources.kubevirt.io/v1/namespaces/${SANDBOX_VM_NS}/virtualmachines/${SANDBOX_VM_NAME}/start" || true)"
  echo "start HTTP ${start_code}"
fi

echo
echo "The guest clones a 30Gi Fedora disk, then cloud-init installs minikube."
echo "Developer Sandbox stops Linux VMs after one hour. Run this task again if that happens."
echo
if [ "${SANDBOX_VM_CONNECT:-1}" = "0" ]; then
  oc get vm,dv,vmi,svc -l app.kubernetes.io/part-of=hello-openshell
  exit 0
fi
exec bash "${ROOT}/scripts/sandbox-vm-connect.sh"
