#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/qresto"
BACKUP_DIR="/var/backups/qresto"
DATE_TAG="$(date +"%Y-%m-%d_%H-%M-%S")"
ARCHIVE_NAME="qresto_backup_${DATE_TAG}.tar.gz"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [ ! -f "$APP_DIR/.env" ]; then
  echo "[ERROR] Missing $APP_DIR/.env"
  exit 1
fi

load_env_file() {
  local env_file="$1"

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      export "$line"
    fi
  done < <(sed $'1s/^\xEF\xBB\xBF//' "$env_file")
}

load_env_file "$APP_DIR/.env"

for key in MONGO_USER MONGO_PASS MONGO_DB; do
  if [ -z "${!key:-}" ]; then
    echo "[ERROR] Missing $key in $APP_DIR/.env"
    exit 1
  fi
done

mkdir -p "$BACKUP_DIR"
mkdir -p "$WORK_DIR/mongo"

docker exec \
  -e MONGO_USER="$MONGO_USER" \
  -e MONGO_PASS="$MONGO_PASS" \
  -e MONGO_DB="$MONGO_DB" \
  qresto_mongo \
  sh -lc 'mongodump --authenticationDatabase admin --username "$MONGO_USER" --password "$MONGO_PASS" --db "$MONGO_DB" --archive --gzip' \
  > "$WORK_DIR/mongo/mongodump.archive.gz"

cp "$APP_DIR/docker-compose.yml" "$WORK_DIR/docker-compose.yml"
cp "$APP_DIR/.env" "$WORK_DIR/.env"
cp "$APP_DIR/letsencrypt/acme.json" "$WORK_DIR/acme.json"

tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$WORK_DIR" .

echo "[OK] Backup created: $BACKUP_DIR/$ARCHIVE_NAME"

# Optional 14-day local retention:
# find "$BACKUP_DIR" -type f -name "qresto_backup_*.tar.gz" -mtime +14 -delete
