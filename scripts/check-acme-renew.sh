#!/usr/bin/env bash
set -euo pipefail

ACME_FILE="${1:-/opt/qresto/letsencrypt/acme.json}"
ALERT_DAYS="${2:-20}"

if [ ! -f "$ACME_FILE" ]; then
  echo "[ERROR] File not found: $ACME_FILE"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[ERROR] jq is required"
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "[ERROR] openssl is required"
  exit 1
fi

echo "=== ACME certificates ==="

jq -r '.[]?.Certificates[]?.certificate' "$ACME_FILE" | while read -r cert_b64; do
  [ -z "$cert_b64" ] && continue

  cert_pem="$(echo "$cert_b64" | base64 -d)"
  subject="$(echo "$cert_pem" | openssl x509 -noout -subject | sed 's/^subject=//')"
  end_raw="$(echo "$cert_pem" | openssl x509 -noout -enddate | cut -d= -f2-)"

  end_epoch="$(date -d "$end_raw" +%s)"
  now_epoch="$(date +%s)"
  days_left="$(( (end_epoch - now_epoch) / 86400 ))"

  echo "Certificate: $subject"
  echo "Expires: $end_raw"
  echo "Days left: $days_left"

  if [ "$days_left" -lt "$ALERT_DAYS" ]; then
    echo "[ALERT] Certificate expires in less than $ALERT_DAYS days"
    exit 2
  fi

  echo "----------------------------------------"
done

echo "[OK] Certificates are above the alert threshold ($ALERT_DAYS days)."
