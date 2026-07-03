# neko-remote — one-command remote browser over Tailscale
# Run `make` or `make help` to see available targets.

SHELL := /bin/bash
COMPOSE := docker compose
ENV_FILE := .env

# Load .env so recipes can echo URLs/ports (defaults mirror docker-compose.yml).
ifneq (,$(wildcard $(ENV_FILE)))
include $(ENV_FILE)
export
endif

HTTP_PORT ?= 8080
MUX_PORT  ?= 52000
ADMIN_USER ?= collab

.DEFAULT_GOAL := help

## ─── Lifecycle ───────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Quick start:  make setup && make up && make url"

.PHONY: setup
setup: ## Install deps (OrbStack, Tailscale), create .env, detect Tailscale IP
	@./setup.sh

.PHONY: up
up: check-env ## Start the stack (detached)
	@$(COMPOSE) up -d
	@$(MAKE) --no-print-directory url

.PHONY: down
down: ## Stop and remove the container
	@$(COMPOSE) down

.PHONY: restart
restart: check-env ## Recreate the container (apply .env changes)
	@$(COMPOSE) up -d --force-recreate
	@$(MAKE) --no-print-directory url

.PHONY: update
update: ## Pull the latest image and recreate
	@$(COMPOSE) pull
	@$(COMPOSE) up -d --force-recreate

## ─── Operations ──────────────────────────────────────────────────────────────

.PHONY: logs
logs: ## Tail server logs (filters chromium/dbus noise)
	@$(COMPOSE) logs -f 2>&1 | grep --line-buffered -vE "dbus|DBus|chromium|DEBG|gcm|ntp"

.PHONY: status
status: ## Show container status
	@$(COMPOSE) ps

.PHONY: ip
ip: ## Refresh TAILSCALE_IP in .env from `tailscale ip -4`
	@ts_ip="$$(tailscale ip -4 2>/dev/null | head -1)"; \
	if [ -z "$$ts_ip" ]; then echo "✗ Tailscale not connected"; exit 1; fi; \
	if grep -q '^TAILSCALE_IP=' $(ENV_FILE); then \
		sed -i '' "s|^TAILSCALE_IP=.*|TAILSCALE_IP=$$ts_ip|" $(ENV_FILE); \
	else echo "TAILSCALE_IP=$$ts_ip" >> $(ENV_FILE); fi; \
	echo "✓ TAILSCALE_IP=$$ts_ip"

.PHONY: url
url: ## Print the access URLs and login
	@echo "──────────────────────────────────────────────"
	@echo "  Local     : http://localhost:$(HTTP_PORT)"
	@if [ -n "$(TAILSCALE_IP)" ]; then echo "  Tailscale : http://$(TAILSCALE_IP):$(HTTP_PORT)"; fi
	@echo "  Admin user: $(ADMIN_USER)   (password in .env)"
	@echo "──────────────────────────────────────────────"

.PHONY: open
open: ## Open the local UI in your browser
	@open "http://localhost:$(HTTP_PORT)"

.PHONY: clean
clean: ## Stop the stack and remove volumes/networks
	@$(COMPOSE) down -v --remove-orphans

## ─── Internal ────────────────────────────────────────────────────────────────

.PHONY: check-env
check-env:
	@if [ ! -f $(ENV_FILE) ]; then \
		echo "✗ No .env found. Run 'make setup' (or 'cp .env.example .env')."; exit 1; fi
	@if ! grep -q '^TAILSCALE_IP=.\+' $(ENV_FILE); then \
		echo "⚠ TAILSCALE_IP is empty — run 'make ip' so remote WebRTC works."; fi
