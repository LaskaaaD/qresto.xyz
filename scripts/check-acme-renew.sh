#!/usr/bin/env bash
set -euo pipefail

ACME_FILE="${1:-/opt/qresto/letsencrypt/acme.json}"
ALERT_DAYS="${2:-20}"

if [ ! -f "$ACME_FILE" ]; then
  echo "[BŁĄD] Nie znaleziono: $ACME_FILE"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[BŁĄD] Brak jq. Zainstaluj: sudo apt install -y jq"
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "[BŁĄD] Brak openssl"
  exit 1
fi

echo "=== Certyfikaty ACME ==="

jq -r '.[]?.Certificates[]?.certificate' "$ACME_FILE" | while read -r cert_b64; do
  [ -z "$cert_b64" ] && continue

  cert_pem="$(echo "$cert_b64" | base64 -d)"
  subject="$(echo "$cert_pem" | openssl x509 -noout -subject | sed 's/^subject=//')"
  end_raw="$(echo "$cert_pem" | openssl x509 -noout -enddate | cut -d= -f2-)"

  end_epoch="$(date -d "$end_raw" +%s)"
  now_epoch="$(date +%s)"
  days_left="$(( (end_epoch - now_epoch) / 86400 ))"

  echo "Cert: $subject"
  echo "Wygasa: $end_raw"
  echo "Pozostało dni: $days_left"

  if [ "$days_left" -lt "$ALERT_DAYS" ]; then
    echo "[ALERT] Cert wygasa za mniej niż $ALERT_DAYS dni"
    exit 2
  fi

  echo "----------------------------------------"
done

echo "[OK] Certyfikaty powyżej progu alarmowego ($ALERT_DAYS dni)."
