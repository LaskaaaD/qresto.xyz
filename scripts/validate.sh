#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_BIN="$(command -v node || command -v node.exe || true)"
DOCKER_BIN="$(command -v docker || true)"
CREATED_ENV=0

cd "$ROOT_DIR"

if [ -z "$NODE_BIN" ]; then
  echo "node is required but was not found in PATH" >&2
  exit 1
fi

if [ -z "$DOCKER_BIN" ]; then
  DOCKER_BIN="$(command -v docker.exe || true)"
fi

if [ -z "$DOCKER_BIN" ]; then
  echo "docker is required but was not found in PATH" >&2
  exit 1
fi

if [ ! -f ".env" ]; then
  cp ".env.example" ".env"
  CREATED_ENV=1
fi

cleanup() {
  if [ "$CREATED_ENV" -eq 1 ]; then
    rm -f "$ROOT_DIR/.env"
  fi
}
trap cleanup EXIT

echo "==> Installing, testing, and auditing app"
(cd app && npm ci && npm test && npm audit --audit-level=moderate)

echo "==> Checking JavaScript syntax"
find app -type f -name "*.js" \
  ! -path "*/node_modules/*" \
  -print0 | xargs -0 -n 1 "$NODE_BIN" --check

echo "==> Checking shell scripts"
find scripts -type f -name "*.sh" -print0 | xargs -0 -n 1 bash -n

echo "==> Validating Docker Compose config"
if ! "$DOCKER_BIN" compose --env-file .env -f docker-compose.yml config >/dev/null 2>&1; then
  if command -v docker.exe >/dev/null 2>&1; then
    docker.exe compose --env-file .env -f docker-compose.yml config >/dev/null
  else
    "$DOCKER_BIN" compose --env-file .env -f docker-compose.yml config >/dev/null
  fi
fi

if command -v ansible-playbook >/dev/null 2>&1; then
  echo "==> Validating Ansible syntax"
  ansible-playbook --syntax-check -i ansible/inventories/prod/hosts.example.yml ansible/setup.yml >/dev/null
else
  echo "==> Skipping Ansible syntax check (ansible-playbook not found)"
fi

echo "==> Validation complete"
