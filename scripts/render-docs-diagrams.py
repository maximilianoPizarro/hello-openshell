#!/usr/bin/env python3
# Write architecture SVGs for GitHub Pages. Official product marks, PatternFly
# dark canvas from ux.redhat.com (#151515 / #1f1f1f / #ee0000). Do not generate
# product logos with an image model.
from __future__ import annotations

import base64
from pathlib import Path
from xml.sax.saxutils import escape

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
SUCCESS = "#3e8635"
SUCCESS_BG = "#1b2b1b"
GOLD = "#f0ab00"
GOLD_BG = "#2a2208"
PURPLE = "#5752d1"
PURPLE_BG = "#1c1833"
INSET = "#151515"


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
  <marker id="arrow-green" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
    <path d="M 0 0 L 10 5 L 0 10 z" fill="{GREEN}"/>
  </marker>
</defs>"""


def svg(width: int, height: int, title: str, body: str, *, bare: bool = False) -> str:
    head = "" if bare else header(title, width)
    # width/height 100% + color-scheme dark fill the viewer; otherwise the UA
    # paints white letterbox bars when the file is opened on its own.
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="100%" height="100%" preserveAspectRatio="xMidYMid meet" style="background-color:{BG};color-scheme:dark;display:block" role="img" aria-label="{escape(title)}">
  <title>{escape(title)}</title>
  <style><![CDATA[:root {{ background-color: {BG}; color-scheme: dark; }}]]></style>
  <rect x="0" y="0" width="{width}" height="{height}" fill="{BG}"/>
  {defs()}
  {head}
  {body}
</svg>
"""


def write(name: str, width: int, height: int, title: str, body: str, *, bare: bool = False) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    text = svg(width, height, title, body, bare=bare)
    if f'style="background-color:{BG}' not in text or 'color-scheme:dark' not in text:
        raise SystemExit(f"{name}: svg root must fill the viewer with {BG}")
    path.write_text(text, encoding="utf-8")
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


def tx(x, y, text, *, fill=TEXT, size=14, weight="400", anchor="start", family="RedHatText") -> str:
    fam = f"{family}, Helvetica, Arial, sans-serif"
    return (
        f'<text x="{x}" y="{y}" text-anchor="{anchor}" fill="{fill}" font-size="{size}" '
        f'font-weight="{weight}" font-family="{fam}">{escape(text)}</text>'
    )


def chip(x: int, y: int, w: int, h: int, text: str) -> str:
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{INSET}" stroke="{LINE}"/>'
        + tx(x + 14, y + h // 2 + 5, text, size=13, fill=MUTED)
    )


def numbered(n: int, x: int, y: int, fill: str) -> str:
    return (
        f'<circle cx="{x}" cy="{y}" r="12" fill="{fill}"/>'
        + tx(x, y + 5, str(n), size=13, weight="700", anchor="middle", fill="#ffffff")
    )


def tint(x: int, y: int, w: int, h: int, bg: str, stroke: str) -> str:
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{bg}" stroke="{stroke}"/>'


def pill(x: int, y: int, w: int, h: int, text: str) -> str:
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{h // 2}" fill="{CARD}" stroke="{LINE}"/>'
        + tx(x + w // 2, y + h // 2 + 5, text, size=13, anchor="middle", fill=MUTED)
    )


def sandbox_ask_path(name: str, copy: dict) -> None:
    # Layout matches the request-path figure: workspace, SSH tunnel, guest VM,
    # sandbox → supervisor → TCP proxy → CPU Ollama. Official marks only.
    w, h = 1440, 860
    body = [
        tx(32, 36, copy["title"], size=24, weight="600", family="RedHatDisplay"),
        tx(32, 60, copy["subtitle"], size=14, fill=MUTED),
        f'<rect x="32" y="70" width="220" height="3" fill="{BAR}"/>',
        image("redhat-logo-on-dark.svg", w - 200, 18, 168, 28),
        # Workspace
        f'<rect x="32" y="100" width="268" height="470" rx="10" fill="{CARD}" stroke="{LINE}"/>',
        f'<rect x="32" y="100" width="268" height="52" rx="10" fill="#0066cc"/>',
        f'<rect x="32" y="136" width="268" height="16" fill="#0066cc"/>',
        image("openshift-dev-spaces.svg", 44, 108, 36, 36),
        tx(88, 132, copy["ws_title"], size=16, weight="700"),
        tx(48, 172, copy["ws_lead"], size=13, fill=MUTED),
        chip(48, 188, 236, 40, copy["ws_cli"]),
        chip(48, 238, 236, 40, copy["ws_task"]),
        chip(48, 288, 236, 40, copy["ws_steps"]),
        chip(48, 338, 236, 40, copy["ws_tunnel"]),
        tx(48, 408, copy["ws_note1"], size=13, fill=MUTED),
        tx(48, 428, copy["ws_note2"], size=13, fill=MUTED),
        f'<line x1="300" y1="358" x2="352" y2="358" stroke="{ACCENT}" stroke-width="2" '
        f'stroke-dasharray="5 4" marker-end="url(#arrow)"/>',
        # Developer Sandbox project
        f'<rect x="352" y="96" width="1056" height="488" rx="14" fill="none" stroke="{ACCENT}" '
        f'stroke-dasharray="7 6"/>',
        f'<rect x="560" y="82" width="{copy["project_w"]}" height="28" rx="14" fill="{ACCENT}"/>',
        tx(560 + copy["project_w"] // 2, 101, copy["project"], size=12, weight="700", anchor="middle"),
        # VM
        f'<rect x="372" y="128" width="700" height="432" rx="10" fill="{CARD}" stroke="{LINE}"/>',
        f'<rect x="372" y="128" width="4" height="432" rx="2" fill="{BAR}"/>',
        image("openshift-virtualization.svg", 392, 144, 36, 36),
        image("fedora.svg", 436, 148, 28, 28),
        f'<rect x="470" y="146" width="32" height="32" rx="6" fill="#ffffff"/>',
        image("rhel.svg", 472, 148, 28, 28),
        tx(512, 158, copy["vm_title"], size=16, weight="700"),
        tx(512, 178, copy["vm_sub"], size=13, fill=MUTED),
        f'<rect x="392" y="196" width="660" height="40" rx="8" fill="{INSET}" stroke="{LINE}"/>',
        image("openshift.svg", 404, 202, 28, 28),
        tx(440, 222, copy["gw"], size=13),
        tx(1028, 222, copy["gw_names"], size=13, anchor="end", fill=MUTED),
        # 1 sandbox
        tint(392, 252, 340, 168, SUCCESS_BG, SUCCESS),
        numbered(1, 412, 276, SUCCESS),
        tx(436, 280, copy["sb_title"], size=15, weight="700"),
        tx(412, 312, copy["sb_1"], size=13, fill=MUTED),
        tx(412, 332, copy["sb_2"], size=13, fill=MUTED),
        tx(412, 352, copy["sb_3"], size=13, fill=MUTED),
        tx(412, 372, copy["sb_4"], size=13, fill=MUTED),
        tx(412, 392, copy["sb_5"], size=13, fill=MUTED),
        # 2 supervisor
        tint(756, 252, 296, 168, GOLD_BG, GOLD),
        numbered(2, 776, 276, GOLD),
        image("openshift.svg", 792, 258, 28, 28),
        tx(828, 280, copy["sv_title"], size=15, weight="700"),
        tx(776, 318, copy["sv_1"], size=13, fill=MUTED),
        tx(776, 338, copy["sv_2"], size=13, fill=MUTED),
        tx(776, 358, copy["sv_3"], size=13, fill=MUTED),
        f'<line x1="732" y1="336" x2="756" y2="336" stroke="{ACCENT}" stroke-width="2" marker-end="url(#arrow)"/>',
        f'<line x1="904" y1="420" x2="904" y2="444" stroke="{ACCENT}" stroke-width="2" marker-end="url(#arrow)"/>',
        # 3 proxy
        tint(392, 440, 660, 100, PURPLE_BG, PURPLE),
        numbered(3, 412, 472, PURPLE),
        tx(436, 468, copy["px_title"], size=15, weight="700"),
        tx(436, 494, copy["px_sub"], size=13, fill=MUTED),
        # 4 Ollama
        f'<rect x="1100" y="236" width="284" height="220" rx="10" fill="{CARD}" stroke="{GREEN}"/>',
        numbered(4, 1120, 264, GREEN),
        image("ollama.svg", 1136, 246, 36, 36),
        tx(1180, 268, copy["ol_title"], size=15, weight="700"),
        tx(1120, 304, copy["ol_1"], size=13, fill=MUTED),
        tx(1120, 324, copy["ol_2"], size=13, fill=MUTED),
        tx(1120, 344, copy["ol_3"], size=13, fill=MUTED),
        tx(1120, 380, copy["ol_5"], size=13, fill=GREEN, weight="700"),
        f'<path d="M1052 490 C1080 490, 1080 346, 1100 346" fill="none" stroke="{GREEN}" '
        f'stroke-width="2" marker-end="url(#arrow-green)"/>',
        # Footer pills
        pill(32, 612, 280, 40, copy["pill1"]),
        pill(328, 612, 300, 40, copy["pill2"]),
        pill(644, 612, 340, 40, copy["pill3"]),
        image("nvidia-logo.svg", 32, 678, 120, 22),
        image("podman-logo.png", 168, 672, 36, 36),
        image("python-logo.svg", 216, 676, 90, 28),
        tx(320, 698, copy["legal1"], size=12, fill=MUTED),
        tx(320, 716, copy["legal2"], size=12, fill=MUTED),
    ]
    write(name, w, h, copy["title"], "\n".join(body), bare=True)


PATH_EN = {
    "title": "How a question travels from the agent to Ollama",
    "subtitle": "hello-openshell · OpenShell 0.1.8 on Red Hat Developer Sandbox",
    "ws_title": "Dev Spaces workspace",
    "ws_lead": "Your workspace terminal:",
    "ws_cli": "OpenShell CLI 0.1.8",
    "ws_task": "Terminal → Run Task…",
    "ws_steps": "A1…A10  ·  B1…B10",
    "ws_tunnel": "SSH tunnel  ·  127.0.0.1:8080",
    "ws_note1": "Resolves in-project DNS names.",
    "ws_note2": "A laptop cannot.",
    "project": "DEVELOPER SANDBOX PROJECT (OPENSHIFT)",
    "project_w": 360,
    "vm_title": "VM u1.large · OpenShift Virtualization",
    "vm_sub": "Fedora + minikube or RHEL + MicroShift",
    "gw": "OpenShell gateway 0.1.8",
    "gw_names": "minikube · microshift",
    "sb_title": "Agent sandbox",
    "sb_1": "Runs examples/ask.py",
    "sb_2": "No network of its own",
    "sb_3": "Policy: UID 65532, filesystem",
    "sb_4": "Profile: only",
    "sb_5": "host.openshell.internal:11434",
    "sv_title": "Supervisor",
    "sv_1": "Makes the only outbound",
    "sv_2": "connection the profile",
    "sv_3": "allows",
    "px_title": "TCP proxy on the VM",
    "px_sub": ":11434 → Ollama ClusterIP in this project",
    "ol_title": "Ollama (CPU)",
    "ol_1": "Model llama3.2:1b",
    "ol_2": "Memory 4Gi, already loaded",
    "ol_3": "GPU quota: 0",
    "ol_5": "5 · replies to the sandbox",
    "pill1": "One u1.large VM at a time",
    "pill2": "VMs stop after one hour",
    "pill3": "The sandbox has no network of its own",
    "legal1": "Independent guide, not affiliated with or endorsed by NVIDIA, Red Hat,",
    "legal2": "or the Python Software Foundation. Marks belong to their owners.",
}

PATH_ES = {
    "title": "Así viaja una pregunta desde el agente hasta Ollama",
    "subtitle": "hello-openshell · OpenShell 0.1.8 en Red Hat Developer Sandbox",
    "ws_title": "Dev Spaces workspace",
    "ws_lead": "Tu terminal de trabajo:",
    "ws_cli": "OpenShell CLI 0.1.8",
    "ws_task": "Terminal → Run Task…",
    "ws_steps": "A1…A10  ·  B1…B10",
    "ws_tunnel": "túnel SSH  ·  127.0.0.1:8080",
    "ws_note1": "Resuelve los nombres internos",
    "ws_note2": "del proyecto; tu laptop no.",
    "project": "PROYECTO DE DEVELOPER SANDBOX (OPENSHIFT)",
    "project_w": 400,
    "vm_title": "VM u1.large · OpenShift Virtualization",
    "vm_sub": "Fedora + minikube o RHEL + MicroShift",
    "gw": "Gateway OpenShell 0.1.8",
    "gw_names": "minikube · microshift",
    "sb_title": "Sandbox del agente",
    "sb_1": "Corre examples/ask.py",
    "sb_2": "Sin red propia",
    "sb_3": "Política: UID 65532, filesystem",
    "sb_4": "Perfil: solo",
    "sb_5": "host.openshell.internal:11434",
    "sv_title": "Supervisor",
    "sv_1": "Hace la única conexión",
    "sv_2": "de salida permitida",
    "sv_3": "por el perfil",
    "px_title": "Proxy TCP en la VM",
    "px_sub": ":11434 → ClusterIP de Ollama en este proyecto",
    "ol_title": "Ollama (CPU)",
    "ol_1": "Modelo llama3.2:1b",
    "ol_2": "Memoria 4Gi, ya cargado",
    "ol_3": "Cuota de GPU: 0",
    "ol_5": "5 · responde a la sandbox",
    "pill1": "Una VM u1.large a la vez",
    "pill2": "Las VMs se apagan a la hora",
    "pill3": "La sandbox no tiene red propia",
    "legal1": "Guía independiente, no afiliada ni respaldada por NVIDIA, Red Hat",
    "legal2": "ni la Python Software Foundation. Las marcas pertenecen a sus titulares.",
}


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
    sandbox_ask_path("sandbox-ask-path.svg", PATH_EN)
    sandbox_ask_path("sandbox-ask-path-es.svg", PATH_ES)
    local_arch()
    local_windows()
    local_flow()
    openshift_arch()
    cloudshell_arch()


if __name__ == "__main__":
    main()
