# Local OpenShell + Ollama quickstart.
# Works from bash on Linux, macOS, and Windows Git Bash.
# Prefer `make up`, `make gateway`, `make ask`, `make down`.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

MODEL_NAME ?= llama3.2:1b
COMPOSE := podman compose -f deploy/compose.yaml
ROOT := $(abspath .)

.PHONY: help up gateway ask down ollama-url

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  make up       Start Ollama and pull $(MODEL_NAME)' \
	  '  make gateway  Install OpenShell 0.1.8 against the Podman socket' \
	  '  make ask      Run examples/ask.py in a hardened Python sandbox' \
	  '  make down     Delete local sandboxes and stop Ollama' \
	  '  make ollama-url  Print the host URL for Ollama'

up:
	@if command -v podman >/dev/null 2>&1; then \
	  if podman machine list --format '{{.Name}} {{.Running}}' 2>/dev/null | grep -q ' false$$'; then \
	    podman machine start; \
	  fi; \
	fi
	$(COMPOSE) up -d
	@echo "Waiting for Ollama..."
	@url="$$(bash scripts/ollama-url.sh)"; \
	  until curl -fsS "$${url}/api/tags" >/dev/null; do sleep 2; done; \
	  echo "Ollama is up at $${url}"
	podman exec ollama ollama pull $(MODEL_NAME)
	@url="$$(bash scripts/ollama-url.sh)"; \
	  curl -fsS "$${url}/v1/models" -H 'Authorization: Bearer fake' | head -c 400; echo

gateway:
	bash scripts/ensure-gateway.sh

ask:
	bash scripts/ask-local.sh

down:
	-@bash -c 'if command -v openshell >/dev/null 2>&1; then openshell sandbox delete hello-agent model-check 2>/dev/null || true; elif command -v podman >/dev/null 2>&1; then MSYS_NO_PATHCONV=1 podman machine ssh -- openshell sandbox delete hello-agent model-check 2>/dev/null || true; fi'
	-$(COMPOSE) down -v

ollama-url:
	@bash scripts/ollama-url.sh
