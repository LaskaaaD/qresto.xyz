#!/usr/bin/env bash
set -euo pipefail

# Przełącznik skali aplikacji pod większy ruch.
# Użycie:
#   bash scripts/traffic-mode.sh normal
#   bash scripts/traffic-mode.sh high
#   bash scripts/traffic-mode.sh status

MODE="${1:-status}"
APP_DIR="/opt/qresto"

if [ ! -d "$APP_DIR" ]; then
  APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fi

cd "$APP_DIR"

if [ ! -f ".env" ]; then
  echo "[BŁĄD] Brak pliku .env w $APP_DIR"
  exit 1
fi

ensure_acme() {
  mkdir -p letsencrypt
  touch letsencrypt/acme.json
  chmod 600 letsencrypt/acme.json
}

upsert_env() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

set_scale() {
  local replicas="$1"

  upsert_env APP_REPLICAS "$replicas"
  ensure_acme

  docker compose --env-file .env up -d --scale app="$replicas"
  echo "[OK] Ustawiono skalę app=${replicas}"
}

case "$MODE" in
  normal)
    set_scale 1
    ;;
  high)
    set_scale 3
    ;;
  status)
    echo "=== Status skali ==="
    grep '^APP_REPLICAS=' .env || echo 'APP_REPLICAS=1 (domyślnie)'
    docker ps --format '{{.Names}}' | grep 'qresto.*app' || true
    ;;
  *)
    echo "Użycie: bash scripts/traffic-mode.sh {normal|high|status}"
    exit 1
    ;;
esac
