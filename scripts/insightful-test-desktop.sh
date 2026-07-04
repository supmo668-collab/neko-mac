#!/usr/bin/env bash
# Manage the optional Insightful test desktop without touching the neko stack.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env.insightful-test"
ENV_EXAMPLE="$ROOT_DIR/.env.insightful-test.example"
COMPOSE_FILE="$ROOT_DIR/docker-compose.insightful-test.yml"

usage() {
  cat <<'USAGE'
Usage: scripts/insightful-test-desktop.sh <command>

Commands:
  init      Create .env.insightful-test and local installer/shared directories
  up        Start the Insightful test desktop
  down      Stop the Insightful test desktop
  restart   Recreate the Insightful test desktop
  logs      Tail logs
  url       Print access URL and installer paths
  clean     Stop and remove the test desktop container

This script does not touch the main neko docker-compose.yml stack.
USAGE
}

need_env() {
  if [ ! -f "$ENV_FILE" ]; then
    echo "No .env.insightful-test found. Run: scripts/insightful-test-desktop.sh init" >&2
    exit 1
  fi
}

compose() {
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

cmd="${1:-help}"
case "$cmd" in
  init)
    if [ ! -f "$ENV_FILE" ]; then
      cp "$ENV_EXAMPLE" "$ENV_FILE"
      echo "Created .env.insightful-test"
    else
      echo ".env.insightful-test already exists"
    fi
    mkdir -p "$ROOT_DIR/insightful-test/installers" "$ROOT_DIR/insightful-test/shared" "$ROOT_DIR/insightful-test/config"
    cat <<EOF

Installer drop path on host:
  $ROOT_DIR/insightful-test/installers

Inside the desktop, installers appear at:
  /config/Downloads/Insightful

Next:
  1. Put the org-admin-provided Insightful installer in the host installer path.
  2. Edit .env.insightful-test and set INSIGHTFUL_UI_PASSWORD.
  3. Run: scripts/insightful-test-desktop.sh up
EOF
    ;;
  up)
    need_env
    compose up -d
    "$0" url
    ;;
  down)
    need_env
    compose down
    ;;
  restart)
    need_env
    compose up -d --force-recreate
    "$0" url
    ;;
  logs)
    need_env
    compose logs -f
    ;;
  url)
    need_env
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    echo "Insightful test desktop:"
    echo "  HTTP : http://localhost:${INSIGHTFUL_HTTP_PORT:-3010}"
    echo "  HTTPS: https://localhost:${INSIGHTFUL_HTTPS_PORT:-3011}"
    echo "  User : ${INSIGHTFUL_UI_USER:-tester}"
    echo "  Pass : see .env.insightful-test (INSIGHTFUL_UI_PASSWORD)"
    echo ""
    echo "Installer path on host:"
    echo "  $ROOT_DIR/insightful-test/installers"
    echo "Installer path in desktop:"
    echo "  /config/Downloads/Insightful"
    ;;
  clean)
    need_env
    compose down --remove-orphans
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
