import http.client
import json
import os
import socket
import time
import urllib.error
import urllib.request

# Two turns in one sandbox. Same DNS and retry path as examples/ask.py.
# Do not use OPENSHELL_* env keys: the CLI reserves that prefix.
_HOST = "host.openshell.internal"
_HOST_IP = os.environ.get("ASK_HOST_IP", "").strip()
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
followup = os.environ.get(
    "ASK_FOLLOWUP",
    "En una frase, por que ese agente no deberia tener red propia?",
)

headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer " + token,
    "Connection": "close",
}


def urlopen_retry(req, timeout, attempts=4):
    last = None
    for i in range(attempts):
        try:
            return urllib.request.urlopen(req, timeout=timeout)
        except (
            http.client.RemoteDisconnected,
            http.client.IncompleteRead,
            ConnectionResetError,
            urllib.error.URLError,
        ) as exc:
            last = exc
            time.sleep(min(8 * (i + 1), 24))
    raise last


def chat(messages):
    payload = {
        "model": model,
        "messages": messages,
        "max_tokens": 80,
        "temperature": 0.2,
        "stream": False,
    }
    body = None
    last = None
    for i in range(4):
        request = urllib.request.Request(
            base + "/chat/completions",
            data=json.dumps(payload).encode(),
            headers=headers,
            method="POST",
        )
        try:
            with urlopen_retry(request, timeout=300, attempts=1) as response:
                body = json.load(response)
            break
        except (
            http.client.RemoteDisconnected,
            http.client.IncompleteRead,
            ConnectionResetError,
            urllib.error.URLError,
        ) as exc:
            last = exc
            time.sleep(min(8 * (i + 1), 24))
    if body is None:
        raise last
    return body["choices"][0]["message"]["content"]


messages = [{"role": "user", "content": prompt}]
first = chat(messages)
print("Turn 1:")
print(first)

messages.append({"role": "assistant", "content": first})
messages.append({"role": "user", "content": followup})
second = chat(messages)
print("Turn 2:")
print(second)
