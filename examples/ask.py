import json
import os
import urllib.request

base = os.environ["OPENAI_BASE_URL"].rstrip("/")
model = os.environ.get("MODEL_NAME", "llama3.2:1b")
token = (
    os.environ.get("RHOAI_API_TOKEN")
    or os.environ.get("OPENAI_API_KEY")
    or "fake"
)

payload = {
    "model": model,
    "messages": [
        {
            "role": "user",
            "content": (
                "Explica en una frase que es un sandbox "
                "y por que un agente deberia correr dentro de uno."
            ),
        }
    ],
    "max_tokens": 120,
    "temperature": 0.2,
}

headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer " + token,
}

request = urllib.request.Request(
    base + "/chat/completions",
    data=json.dumps(payload).encode(),
    headers=headers,
)

with urllib.request.urlopen(request, timeout=180) as response:
    body = json.load(response)

print(body["choices"][0]["message"]["content"])
