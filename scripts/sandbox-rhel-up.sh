#!/bin/bash
# Create the RHEL 9 terminal VM. It does not install minikube or connect
# a gateway. Log in as cloud-user.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=sandbox-vm-lib.sh
source "${ROOT}/scripts/sandbox-vm-lib.sh"

VM_NAME="rhel-vm"

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
if ! oc get datasource rhel9 -n openshift-virtualization-os-images >/dev/null 2>&1; then
  echo "The rhel9 DataSource is not readable in openshift-virtualization-os-images."
  exit 1
fi

if oc get vm "${VM_NAME}" >/dev/null 2>&1; then
  echo "VM ${VM_NAME} already exists. Leaving its disk and cloud-init alone."
else
  pass_file="${SANDBOX_VM_CFG}/rhel.password"
  if [ ! -f "${pass_file}" ]; then
    openssl rand -hex 12 > "${pass_file}"
    chmod 600 "${pass_file}"
  fi
  rendered="$(mktemp)"
  trap 'rm -f "${rendered}"' EXIT
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
    + "/scripts/microshift-guest-boot.sh"
)
command = (
    "i=0; u=%s; while [ $i -lt 12 ]; do curl -fsSL -o /usr/local/sbin/microshift-guest-boot.sh $u && break; i=$((i+1)); sleep 5; done; test -s /usr/local/sbin/microshift-guest-boot.sh && bash /usr/local/sbin/microshift-guest-boot.sh || true"
    % url
)
user_data = """#cloud-config
user: cloud-user
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
if size > 1400:
    raise SystemExit("cloud-init userData is %s bytes. Keep it under 1400 so the sandbox can add a key." % size)
print("cloud-init userData bytes:", size)
text = (root / "deploy" / "sandbox-rhel-vm.yaml").read_text(encoding="utf-8").replace("\r\n", "\n")
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
    raise SystemExit("deploy/sandbox-rhel-vm.yaml is missing __CLOUD_INIT__")
rendered = "\n".join(lines) + "\n"
if any(line.strip() == "__CLOUD_INIT__" for line in rendered.split("\n")):
    raise SystemExit("cloud-init placeholder survived rendering")
Path(os.environ["OUT"]).write_bytes(rendered.encode("utf-8"))
PY
  apply_path="${rendered}"
  if command -v cygpath >/dev/null 2>&1; then
    apply_path="$(cygpath -w "${rendered}")"
  fi
  echo "applying ${apply_path}"
  MSYS_NO_PATHCONV=1 oc apply -f "${apply_path}"
  echo "VM ${VM_NAME} created."
fi

status="$(oc get vm "${VM_NAME}" -o jsonpath='{.status.printableStatus}')"
if [ "${status}" != "Running" ]; then
  server="$(oc whoami --show-server)"
  start_code="$(curl -sS -o "${SANDBOX_VM_CFG}/rhel-start.json" -w "%{http_code}" -k -X PUT \
    -H "Authorization: Bearer $(oc whoami -t)" \
    -H "Content-Type: application/json" \
    -d '{}' \
    "${server}/apis/subresources.kubevirt.io/v1/namespaces/${SANDBOX_VM_NS}/virtualmachines/${VM_NAME}/start" || true)"
  echo "start HTTP ${start_code}"
fi

pass_file="${SANDBOX_VM_CFG}/rhel.password"
echo
echo "Guest: RHEL 9, user cloud-user. Cloud-init installs MicroShift, not minikube."
echo "Then run: bash scripts/sandbox-rhel-connect.sh"
echo "That step needs ~/.config/hello-openshell/openshift-pull-secret."
echo "Developer Sandbox stops Linux VMs after one hour. Run this task again if that happens."
echo "Console password file: ${pass_file}"
echo
echo "From this workspace, once sshd answers:"
echo "  ssh -i ${SANDBOX_VM_KEY} -o IdentitiesOnly=yes cloud-user@${VM_NAME}.${SANDBOX_VM_NS}.svc.cluster.local"
echo
echo "From a laptop, the cluster DNS name does not resolve. Forward the service, then SSH:"
echo "  oc port-forward svc/${VM_NAME} 2222:22"
echo "  ssh -i ${SANDBOX_VM_KEY} -p 2222 -o IdentitiesOnly=yes cloud-user@127.0.0.1"
echo
oc get vm,dv,vmi,svc "${VM_NAME}" 2>/dev/null || oc get vm,dv,svc -l app.kubernetes.io/name=rhel
