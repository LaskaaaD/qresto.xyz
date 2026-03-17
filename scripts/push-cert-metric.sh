#!/usr/bin/env bash
set -euo pipefail

# Wysyła metrykę liczby dni do wygaśnięcia certyfikatu do Zabbix Trapper.
# Wymaga zabbix_sender i openssl.

load_env_file() {
  local env_file="$1"

  [ -f "$env_file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      export "$line"
    fi
  done < <(sed $'1s/^\xEF\xBB\xBF//' "$env_file")
}

# Dla uruchomień z crona pobierz wartości z /opt/qresto/.env (jeśli istnieje)
load_env_file "/opt/qresto/.env"

APP_DOMAIN="${APP_DOMAIN:-}"
ZABBIX_SERVER="${ZABBIX_SERVER:-127.0.0.1}"
ZABBIX_HOSTNAME="${ZABBIX_HOSTNAME:-qresto-vps-agent}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
TELEGRAM_CERT_ALERT_DAYS="${TELEGRAM_CERT_ALERT_DAYS:-20}"
CERT_ALERT_STATE_FILE="${CERT_ALERT_STATE_FILE:-/var/tmp/qresto-cert-alert.state}"

if [ -z "$APP_DOMAIN" ]; then
  echo "[BŁĄD] Ustaw APP_DOMAIN"
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "[BŁĄD] Brak openssl"
  exit 1
fi

if ! command -v zabbix_sender >/dev/null 2>&1; then
  echo "[BŁĄD] Brak zabbix_sender (zainstaluj zabbix-sender)"
  exit 1
fi

end_raw="$(echo | openssl s_client -servername "$APP_DOMAIN" -connect "$APP_DOMAIN:443" 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2-)"
end_epoch="$(date -d "$end_raw" +%s)"
now_epoch="$(date +%s)"
days_left="$(( (end_epoch - now_epoch) / 86400 ))"

zabbix_sender -z "$ZABBIX_SERVER" -s "$ZABBIX_HOSTNAME" -k qresto.acme.days.left -o "$days_left"
echo "[OK] Wysłano qresto.acme.days.left=$days_left"

send_telegram_alert() {
  local message="$1"
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${message}" >/dev/null
}

if [ "$days_left" -lt "$TELEGRAM_CERT_ALERT_DAYS" ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
  stamp="$(date +%F)"
  last_sent=""

  if [ -f "$CERT_ALERT_STATE_FILE" ]; then
    last_sent="$(cat "$CERT_ALERT_STATE_FILE" 2>/dev/null || true)"
  fi

  if [ "$last_sent" != "$stamp" ]; then
    msg="⚠️ QResto: cert dla ${APP_DOMAIN} wygasa za ${days_left} dni (prog: ${TELEGRAM_CERT_ALERT_DAYS})."
    if send_telegram_alert "$msg"; then
      echo "$stamp" > "$CERT_ALERT_STATE_FILE"
      echo "[OK] Wysłano alert Telegram o certyfikacie"
    else
      echo "[WARN] Nie udało się wysłać alertu Telegram"
    fi
  fi
fi
