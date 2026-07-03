#!/usr/bin/env bash
# setup.sh — bootstrap prerequisites for neko-remote on macOS.
# Installs OrbStack (Docker) + Tailscale, creates .env, and fills in TAILSCALE_IP.
# After this, run `make up`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"

step() { echo; echo "▶ $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*"; }

# ── 1. Homebrew ───────────────────────────────────────────────────────────────
step "Checking Homebrew"
if ! command -v brew &>/dev/null; then
  echo "  Installing Homebrew…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  ok "Homebrew present"
fi

# ── 2. OrbStack (Docker runtime) ─────────────────────────────────────────────
step "Checking OrbStack"
if [ ! -d "/Applications/OrbStack.app" ] && ! command -v orb &>/dev/null; then
  echo "  Installing OrbStack…"
  brew install --cask orbstack
fi
if ! docker info &>/dev/null; then
  echo "  Starting OrbStack…"
  open -a OrbStack || true
  echo "  Waiting for the Docker daemon…"
  for _ in {1..30}; do docker info &>/dev/null && break; sleep 2; done
fi
if ! docker info &>/dev/null; then
  warn "Docker daemon not reachable — open OrbStack, then re-run."; exit 1
fi
ok "Docker is up"

# ── 3. Tailscale ─────────────────────────────────────────────────────────────
step "Checking Tailscale"
if ! command -v tailscale &>/dev/null && [ ! -e "/Applications/Tailscale.app" ]; then
  echo "  Installing Tailscale…"
  brew install --cask tailscale
fi
if ! command -v tailscale &>/dev/null; then
  # CLI ships inside the app bundle when installed via cask
  export PATH="$PATH:/Applications/Tailscale.app/Contents/MacOS"
fi
if ! tailscale status &>/dev/null; then
  echo "  Launching Tailscale — sign in from the menu bar…"
  open -a Tailscale || true
  echo "  Then run:  tailscale login   (or connect via the menu bar) and re-run this script."
  exit 0
fi
ok "Tailscale connected"

# ── 4. .env ──────────────────────────────────────────────────────────────────
step "Preparing .env"
if [ ! -f "$ENV_FILE" ]; then
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  ok "Created .env from .env.example — edit passwords before going live!"
else
  ok ".env already exists (leaving it untouched)"
fi

# ── 5. Tailscale IP ──────────────────────────────────────────────────────────
step "Detecting Tailscale IPv4"
TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"
if [ -z "$TS_IP" ]; then warn "Could not detect Tailscale IP"; exit 1; fi
if grep -q '^TAILSCALE_IP=' "$ENV_FILE"; then
  sed -i '' "s|^TAILSCALE_IP=.*|TAILSCALE_IP=${TS_IP}|" "$ENV_FILE"
else
  echo "TAILSCALE_IP=${TS_IP}" >> "$ENV_FILE"
fi
ok "TAILSCALE_IP=${TS_IP}"

echo
echo "Done. Next:"
echo "  1. Edit .env passwords (ADMIN_PASSWORD / VIEWER_PASSWORD)"
echo "  2. make up"
