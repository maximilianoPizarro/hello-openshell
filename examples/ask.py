import json
import os
import socket
import urllib.request

# Kubernetes sandboxes have no DNS. OpenShell injects host.openshell.internal
# when server.hostGatewayIP is set. If getaddrinfo still fails, map the name
# to OPENSHELL_HOST_IP (the guest address the supervisor can dial).
_HOST = "host.openshell.internal"
_HOST_IP = os.environ.get("OPENSHELL_HOST_IP", "").strip()
_orig_getaddrinfo = socket.getaddrinfo


def _getaddrinfo(host, port, *args, **kwargs):
    if host == _HOST:
        try:
            return _orig_getaddrinfo(host, port, *args, **kwargs)
        except OSError:
            if not _HOST_IP:
                raise
            port_i = 0 if port is None else int(port)
            return [
                (
                    socket.AF_INET,
                    socket.SOCK_STREAM,
                    socket.IPPROTO_TCP,
                    "",
                    (_HOST_IP, port_i),
                )
            ]
    return _orig_getaddrinfo(host, port, *args, **kwargs)


socket.getaddrinfo = _getaddrinfo

base = os.environ["OPENAI_BASE_URL"].rstrip("/")
model = os.environ.get("MODEL_NAME", "llama3.2:1b")
token = (
    os.environ.get("RHOAI_API_TOKEN")
    or os.environ.get("OPENAI_API_KEY")
    or "fake"
)
prompt = os.environ.get(
    "ASK_PROMPT",
    "Explica en una frase que es un sandbox "
    "y por que un agente deberia correr dentro de uno.",
)

headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer " + token,
}

if os.environ.get("ASK_LIST_MODELS") == "1":
    models_req = urllib.request.Request(base + "/models", headers=headers)
    with urllib.request.urlopen(models_req, timeout=60) as models_res:
        print(models_res.read().decode())

payload = {
    "model": model,
    "messages": [{"role": "user", "content": prompt}],
    "max_tokens": 120,
    "temperature": 0.2,
}

request = urllib.request.Request(
    base + "/chat/completions",
    data=json.dumps(payload).encode(),
    headers=headers,
)

with urllib.request.urlopen(request, timeout=180) as response:
    body = json.load(response)

print(body["choices"][0]["message"]["content"])
