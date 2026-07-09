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

## ─── Insightful work VM (Lima, full amd64) ──────────────────────────────────

VM := scripts/insightful-vm.sh

.PHONY: vm-create
vm-create: ## Build & start the Insightful work VM (Chrome + Workpuls desktop)
	@$(VM) create

.PHONY: vm-up
vm-up: ## Start the existing work VM
	@$(VM) start

.PHONY: vm-down
vm-down: ## Stop the work VM
	@$(VM) stop

.PHONY: vm-url
vm-url: ## Print the work VM desktop URLs (local + Tailscale)
	@$(VM) url

.PHONY: vm-shell
vm-shell: ## Open a shell inside the work VM
	@$(VM) shell

.PHONY: vm-tailscale
vm-tailscale: ## Join the work VM to your Tailnet (interactive auth)
	@$(VM) tailscale

.PHONY: vm-install
vm-install: ## Launch the Workpuls installer inside the work VM
	@$(VM) install

.PHONY: vm-services
vm-services: ## Enable & start the VM desktop services (VNC + noVNC)
	@$(VM) services

.PHONY: vm-ensure
vm-ensure: ## Start VM + desktop services if not already running (idempotent)
	@$(VM) ensure

.PHONY: vm-autostart
vm-autostart: ## Keep the VM always-on: install launchd agent (starts at login)
	@$(VM) autostart

.PHONY: vm-autostart-remove
vm-autostart-remove: ## Stop keeping the VM always-on (remove launchd agent)
	@$(VM) autostart-remove

.PHONY: vm-delete
vm-delete: ## Delete the work VM (destructive)
	@$(VM) delete

## ─── Parallel vmnet variant (lower-latency net; separate, independent VM) ────
# Same commands, prefixed `vm-vmnet-`. Independent instance (insightful-vm-vmnet),
# config (vm/lima-insightful-vmnet.yaml), host port :6080, launchd agent
# (com.insightful.vm.vmnet) — does NOT touch the original slirp VM above.
# Prereq: brew install socket_vmnet && limactl sudoers | sudo tee /etc/sudoers.d/lima
# See docs/VM-VARIANTS.md.

VMNET := INSIGHTFUL_VARIANT=vmnet scripts/insightful-vm.sh

.PHONY: vm-vmnet-create
vm-vmnet-create: ## [vmnet] Build & start the parallel vmnet VM (desktop on host :6080)
	@$(VMNET) create

.PHONY: vm-vmnet-up
vm-vmnet-up: ## [vmnet] Start the existing vmnet VM
	@$(VMNET) start

.PHONY: vm-vmnet-down
vm-vmnet-down: ## [vmnet] Stop the vmnet VM
	@$(VMNET) stop

.PHONY: vm-vmnet-url
vm-vmnet-url: ## [vmnet] Print the vmnet VM desktop URLs
	@$(VMNET) url

.PHONY: vm-vmnet-shell
vm-vmnet-shell: ## [vmnet] Open a shell inside the vmnet VM
	@$(VMNET) shell

.PHONY: vm-vmnet-tailscale
vm-vmnet-tailscale: ## [vmnet] Join the vmnet VM to your Tailnet (interactive)
	@$(VMNET) tailscale

.PHONY: vm-vmnet-install
vm-vmnet-install: ## [vmnet] Launch the Workpuls installer inside the vmnet VM
	@$(VMNET) install

.PHONY: vm-vmnet-services
vm-vmnet-services: ## [vmnet] Start the vmnet VM desktop services (VNC + noVNC)
	@$(VMNET) services

.PHONY: vm-vmnet-ensure
vm-vmnet-ensure: ## [vmnet] Start vmnet VM + services if not running (idempotent)
	@$(VMNET) ensure

.PHONY: vm-vmnet-autostart
vm-vmnet-autostart: ## [vmnet] Keep the vmnet VM always-on (separate launchd agent)
	@$(VMNET) autostart

.PHONY: vm-vmnet-autostart-remove
vm-vmnet-autostart-remove: ## [vmnet] Stop keeping the vmnet VM always-on
	@$(VMNET) autostart-remove

.PHONY: vm-vmnet-delete
vm-vmnet-delete: ## [vmnet] Delete the vmnet VM (destructive)
	@$(VMNET) delete

.PHONY: vm-vmnet-serve
vm-vmnet-serve: ## [vmnet] Serve the KasmVNC desktop to your tailnet over HTTPS (remote collaborators)
	@if tailscale cert 2>&1 | grep -q "not enabled"; then \
		echo "✗ Enable HTTPS certs first: https://login.tailscale.com/admin/dns  (HTTPS Certificates)"; \
		exit 1; fi
	@tailscale serve --bg http://127.0.0.1:6080
	@echo "── Now serving KasmVNC to your tailnet (WireGuard-encrypted, real HTTPS) ──"
	@tailscale serve status
	@echo "Then: share the 'macbook-pro' node with the collaborator (admin → Machines → Share)."

.PHONY: vm-vmnet-serve-stop
vm-vmnet-serve-stop: ## [vmnet] Stop serving to the tailnet (back to local-only)
	@tailscale serve reset && echo "Tailnet serve stopped — KasmVNC is local-only again."

## ─── Internal ────────────────────────────────────────────────────────────────

.PHONY: check-env
check-env:
	@if [ ! -f $(ENV_FILE) ]; then \
		echo "✗ No .env found. Run 'make setup' (or 'cp .env.example .env')."; exit 1; fi
	@if ! grep -q '^TAILSCALE_IP=.\+' $(ENV_FILE); then \
		echo "⚠ TAILSCALE_IP is empty — run 'make ip' so remote WebRTC works."; fi
