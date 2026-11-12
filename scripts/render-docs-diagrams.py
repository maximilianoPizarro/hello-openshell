#!/usr/bin/env python3
# Write architecture SVGs for GitHub Pages. Official product marks, PatternFly
# dark canvas from ux.redhat.com (#151515 / #1f1f1f / #ee0000). Do not generate
# product logos with an image model.
from __future__ import annotations

import base64
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOGO = ROOT / "docs" / "assets" / "logos"
OUT = ROOT / "docs" / "assets" / "diagrams"

BG = "#151515"
CARD = "#1f1f1f"
LINE = "#3c3f42"
TEXT = "#ffffff"
MUTED = "#e0e0e0"
BAR = "#ee0000"
ACCENT = "#0066cc"
GREEN = "#76b900"
DENY = "#c9190b"


def data_uri(path: Path, *, on_dark: bool = False) -> str:
    raw = path.read_bytes()
    mime = "image/png" if path.suffix.lower() == ".png" else "image/svg+xml"
    if on_dark and path.suffix.lower() == ".svg":
        text = raw.decode("utf-8")
        if 'fill="' not in text:
            text = text.replace("<svg", '<svg fill="#ffffff"', 1)
        raw = text.encode("utf-8")
    return f"data:{mime};base64,{base64.b64encode(raw).decode()}"


LIGHT_GLYPHS = {"fedora.svg", "kubernetes.svg", "ollama.svg", "minikube.svg"}


def image(name: str, x: int, y: int, w: int, h: int) -> str:
    uri = data_uri(LOGO / name, on_dark=name in LIGHT_GLYPHS)
    return (
        f'<image href="{uri}" x="{x}" y="{y}" width="{w}" height="{h}" '
        f'preserveAspectRatio="xMidYMid meet"/>'
    )


def card(x: int, y: int, w: int, h: int, title: str, logo: str | None, sub: str = "") -> str:
    logo_h = 44 if logo else 0
    logo_y = y + 16
    title_y = y + (70 if logo else 36)
    bits = [
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{CARD}" stroke="{LINE}"/>',
        f'<rect x="{x}" y="{y}" width="4" height="{h}" rx="2" fill="{BAR}"/>',
    ]
    if logo:
        bits.append(image(logo, x + (w - 120) // 2, logo_y, 120, logo_h))
    bits.append(
        f'<text x="{x + w // 2}" y="{title_y}" text-anchor="middle" '
        f'fill="{TEXT}" font-size="15" font-family="RedHatText, Helvetica, Arial, sans-serif">{title}</text>'
    )
    if sub:
        bits.append(
            f'<text x="{x + w // 2}" y="{title_y + 20}" text-anchor="middle" '
            f'fill="{MUTED}" font-size="12" font-family="RedHatText, Helvetica, Arial, sans-serif">{sub}</text>'
        )
    return "\n".join(bits)


def arrow(x1: int, y1: int, x2: int, y2: int, color: str = ACCENT) -> str:
    return (
        f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" '
        f'stroke-width="2" marker-end="url(#arrow)"/>'
    )


def header(title: str, width: int) -> str:
    return (
        f'<text x="32" y="36" fill="{TEXT}" font-size="22" font-weight="600" '
        f'font-family="RedHatDisplay, Helvetica, Arial, sans-serif">{title}</text>'
        f'<rect x="32" y="48" width="{min(220, width - 64)}" height="3" fill="{BAR}"/>'
        + image("redhat-logo-on-dark.svg", width - 200, 14, 168, 28)
    )


def defs() -> str:
    return f"""<defs>
  <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
    <path d="M 0 0 L 10 5 L 0 10 z" fill="{ACCENT}"/>
  </marker>
</defs>"""


def svg(width: int, height: int, title: str, body: str) -> str:
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" role="img" aria-label="{title}">
  <title>{title}</title>
  <rect width="{width}" height="{height}" fill="{BG}"/>
  {defs()}
  {header(title, width)}
  {body}
</svg>
"""


def write(name: str, width: int, height: int, title: str, body: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    path.write_text(svg(width, height, title, body), encoding="utf-8")
    print(path, path.stat().st_size)


def sandbox() -> None:
    body = "\n".join(
        [
            card(400, 72, 320, 110, "Dev Spaces workspace", "openshift-dev-spaces.svg", "OpenShell CLI"),
            arrow(560, 182, 280, 230),
            arrow(560, 182, 840, 230),
            card(80, 230, 400, 150, "Fedora VM  ·  minikube", "fedora.svg", "OpenShell gateway 0.1.8"),
            card(640, 230, 400, 150, "RHEL VM  ·  MicroShift", "rhel.svg", "OpenShell gateway 0.1.8"),
            image("openshift-virtualization.svg", 96, 248, 36, 36),
            image("openshift.svg", 656, 248, 36, 36),
            arrow(280, 380, 280, 430),
            arrow(840, 380, 840, 430),
            card(80, 430, 400, 130, "OpenShell sandbox", "python-logo.svg", "ask.py  ·  hi-python policy"),
            card(640, 430, 400, 130, "Ollama llama3.2:1b", "ollama.svg", "CPU in the user project"),
            arrow(480, 495, 640, 495),
            '<text x="560" y="488" text-anchor="middle" fill="#e0e0e0" font-size="12" font-family="RedHatText, Helvetica, Arial, sans-serif">host.openshell.internal:11434</text>',
            f'<text x="32" y="600" fill="{MUTED}" font-size="13" font-family="RedHatText, Helvetica, Arial, sans-serif">One u1.large guest at a time. GPU quota is 0. The sandbox has no network of its own.</text>',
            image("nvidia-logo.svg", 32, 616, 120, 22),
        ]
    )
    write("sandbox-architecture.svg", 1120, 660, "Developer Sandbox architecture", body)


def sandbox_flow() -> None:
    body = "\n".join(
        [
            card(40, 90, 340, 130, "1. Profile ollama", "nvidia-logo.svg", "host.openshell.internal:11434"),
            card(410, 90, 340, 130, "2. Provider ollama", "ollama.svg", "openshell provider create"),
            card(780, 90, 340, 130, "3. Agent sandbox", "python-logo.svg", "hello-ask / hello-agent"),
            arrow(380, 155, 410, 155),
            arrow(750, 155, 780, 155),
            card(40, 260, 250, 130, "ask.py POST", "python-logo.svg", "/v1/chat/completions"),
            card(320, 260, 250, 130, "Policy ALLOW", "nvidia-logo.svg", "hi-python  ·  UID 65532"),
            card(600, 260, 250, 130, "Supervisor", "openshift.svg", "guest :11434 proxy"),
            card(880, 260, 250, 130, "Ollama", "ollama.svg", "llama3.2:1b in the project"),
            arrow(290, 325, 320, 325),
            arrow(570, 325, 600, 325),
            arrow(850, 325, 880, 325),
            f'<text x="40" y="440" fill="{MUTED}" font-size="14" font-family="RedHatText, Helvetica, Arial, sans-serif">Ask imports the profile, creates the provider, then runs ask.py inside the sandbox. The sandbox has no network of its own.</text>',
        ]
    )
    write("sandbox-ask-flow.svg", 1170, 480, "Profile, provider, and agent", body)


def local_arch() -> None:
    body = "\n".join(
        [
            card(40, 90, 250, 150, "OpenShell CLI", "nvidia-logo.svg", "0.1.8"),
            card(330, 90, 250, 150, "Podman", "podman-logo.png", "gateway + sandbox"),
            card(620, 90, 250, 150, "Python sandbox", "python-logo.svg", "hi-python policy"),
            card(910, 90, 250, 150, "Ollama", "ollama.svg", "llama3.2:1b  ·  3 GiB"),
            arrow(290, 165, 330, 165),
            arrow(580, 165, 620, 165),
            arrow(870, 165, 910, 165),
            f'<text x="40" y="290" fill="{MUTED}" font-size="14" font-family="RedHatText, Helvetica, Arial, sans-serif">host.openshell.internal:11434  ·  the sandbox has no network of its own</text>',
        ]
    )
    write("local-architecture.svg", 1200, 330, "Local architecture", body)


def local_windows() -> None:
    body = "\n".join(
        [
            card(40, 90, 340, 160, "Windows host", "python-logo.svg", "make ollama-url or mirrored WSL"),
            card(430, 90, 340, 160, "Podman machine", "podman-logo.png", "127.0.0.1:11434 inside the VM"),
            card(820, 90, 340, 160, "OpenShell sandbox", "nvidia-logo.svg", "host.openshell.internal:11434"),
            arrow(380, 170, 430, 170),
            arrow(770, 170, 820, 170),
            f'<text x="40" y="300" fill="{MUTED}" font-size="14" font-family="RedHatText, Helvetica, Arial, sans-serif">Loopback from inside the sandbox is blocked. Use host.openshell.internal.</text>',
        ]
    )
    write("local-windows-net.svg", 1200, 340, "Where port 11434 is reachable", body)


def local_flow() -> None:
    body = "\n".join(
        [
            card(40, 90, 250, 140, "POST ask.py", "python-logo.svg", "chat/completions"),
            card(330, 90, 250, 140, "Policy ALLOW", "nvidia-logo.svg", "profile ollama"),
            card(620, 90, 250, 140, "Supervisor", "podman-logo.png", "host connection"),
            card(910, 90, 250, 140, "Model reply", "ollama.svg", "llama3.2:1b"),
            arrow(290, 160, 330, 160),
            arrow(580, 160, 620, 160),
            arrow(870, 160, 910, 160),
        ]
    )
    write("local-flow.svg", 1200, 280, "ask.py through the sandbox", body)


def openshift_arch() -> None:
    body = "\n".join(
        [
            card(40, 90, 250, 150, "OpenShell CLI", "nvidia-logo.svg", "port-forward 8080"),
            card(330, 90, 250, 150, "OpenShell gateway", "openshift.svg", "restricted-v2"),
            card(620, 90, 250, 150, "Sandbox", "python-logo.svg", "RHOAI_API_TOKEN"),
            card(910, 90, 250, 150, "Granite on GPU", "openshift-ai.svg", "vLLM  ·  one GPU"),
            arrow(290, 165, 330, 165),
            arrow(580, 165, 620, 165),
            arrow(870, 165, 910, 165),
            f'<text x="40" y="290" fill="{MUTED}" font-size="14" font-family="RedHatText, Helvetica, Arial, sans-serif">The supervisor injects the token. The sandbox never stores the key.</text>',
        ]
    )
    write("openshift-architecture.svg", 1200, 330, "OpenShift AI architecture", body)


def cloudshell_arch() -> None:
    body = "\n".join(
        [
            card(80, 90, 280, 150, "Google Cloud Shell", "kubernetes.svg", "minikube in this VM"),
            card(460, 90, 280, 150, "OpenShell gateway", "nvidia-logo.svg", "chart 0.1.8 installs"),
            card(840, 90, 280, 150, "Sandbox", "python-logo.svg", "does not run"),
            arrow(360, 165, 460, 165),
            f'<line x1="740" y1="165" x2="840" y2="165" stroke="{DENY}" stroke-width="3"/>',
            f'<text x="790" y="150" text-anchor="middle" fill="{DENY}" font-size="18" font-weight="700">×</text>',
            f'<text x="80" y="290" fill="{MUTED}" font-size="14" font-family="RedHatText, Helvetica, Arial, sans-serif">This kernel has no CONFIG_SECURITY_LANDLOCK. OpenShell 0.1.8 sandboxes need Landlock ABI v3. Not a GKE cluster.</text>',
        ]
    )
    write("cloudshell-architecture.svg", 1200, 340, "Cloud Shell limitation", body)


def main() -> None:
    sandbox()
    sandbox_flow()
    local_arch()
    local_windows()
    local_flow()
    openshift_arch()
    cloudshell_arch()


if __name__ == "__main__":
    main()
