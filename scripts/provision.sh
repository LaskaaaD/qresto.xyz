#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"/..

echo "====== QRESTO VPS PROVISIONING ======"

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "[BŁĄD] Brak narzędzia 'ansible-playbook'."
  echo "Zainstaluj Ansible i uruchom skrypt ponownie."
  exit 1
fi

prompt_default() {
  local message="$1"
  local default_value="$2"
  local result

  read -r -p "$message [$default_value]: " result
  if [ -z "$result" ]; then
    result="$default_value"
  fi

  echo "$result"
}

SERVER_IP=""
while [ -z "$SERVER_IP" ]; do
  read -r -p "Podaj IP VPS: " SERVER_IP
  if [ -z "$SERVER_IP" ]; then
    echo "[BŁĄD] IP nie może być puste."
  fi
done

SSH_USER="$(prompt_default "Podaj użytkownika SSH do pierwszego połączenia" "root")"
SSH_PORT="$(prompt_default "Podaj port SSH do pierwszego połączenia" "22")"
if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
  echo "[BŁĄD] Niepoprawny port SSH: $SSH_PORT"
  exit 1
fi

TARGET_SSH_PORT="$(prompt_default "Podaj docelowy port SSH po hardeningu" "$SSH_PORT")"
if [[ ! "$TARGET_SSH_PORT" =~ ^[0-9]+$ ]] || [ "$TARGET_SSH_PORT" -lt 1 ] || [ "$TARGET_SSH_PORT" -gt 65535 ]; then
  echo "[BŁĄD] Niepoprawny docelowy port SSH: $TARGET_SSH_PORT"
  exit 1
fi

SSH_PRIVATE_KEY="$(prompt_default "Podaj ścieżkę do klucza prywatnego SSH" "$HOME/.ssh/id_ed25519")"

if [ ! -f "$SSH_PRIVATE_KEY" ]; then
  echo "[BŁĄD] Nie znaleziono klucza prywatnego: $SSH_PRIVATE_KEY"
  exit 1
fi

DEFAULT_PUB_KEY="$SSH_PRIVATE_KEY.pub"
if [ ! -f "$DEFAULT_PUB_KEY" ]; then
  DEFAULT_PUB_KEY="$HOME/.ssh/id_ed25519.pub"
fi
SSH_PUBLIC_KEY="$(prompt_default "Podaj ścieżkę do klucza publicznego (dla nowego usera deploy)" "$DEFAULT_PUB_KEY")"

if [ ! -f "$SSH_PUBLIC_KEY" ]; then
  echo "[BŁĄD] Nie znaleziono klucza publicznego: $SSH_PUBLIC_KEY"
  exit 1
fi

DEPLOY_USER="$(prompt_default "Podaj nazwę docelowego użytkownika deploy" "qresto_user")"
if [[ ! "$DEPLOY_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "[BŁĄD] Niepoprawna nazwa użytkownika: $DEPLOY_USER"
  exit 1
fi

ROOT_DOMAIN=""
while [ -z "$ROOT_DOMAIN" ]; do
  read -r -p "Podaj domenę główną (np. qresto.xyz): " ROOT_DOMAIN
  if [ -z "$ROOT_DOMAIN" ]; then
    echo "[BŁĄD] Domena główna nie może być pusta."
  fi
done

APP_DOMAIN="$(prompt_default "Podaj domenę aplikacji" "$ROOT_DOMAIN")"
APP_WWW_DOMAIN="$(prompt_default "Podaj domenę WWW" "www.$ROOT_DOMAIN")"
ZABBIX_DOMAIN="$(prompt_default "Podaj domenę Zabbix" "zabbix.$ROOT_DOMAIN")"
SSL_EMAIL="$(prompt_default "Podaj e-mail dla certyfikatów Let's Encrypt" "admin@$ROOT_DOMAIN")"

echo "[INFO] Tworzę ansible/inventory dla hosta $SERVER_IP"
cat > ansible/inventory <<EOF
[vps]
target ansible_host=$SERVER_IP ansible_port=$SSH_PORT ansible_ssh_private_key_file=$SSH_PRIVATE_KEY
EOF

echo "[INFO] Uruchamiam Ansible provisioning..."
ansible-playbook -i ansible/inventory ansible/setup.yml \
  -e "ansible_user=$SSH_USER" \
  -e "ansible_become=yes" \
  -e "initial_ssh_port=$SSH_PORT" \
  -e "deploy_user=$DEPLOY_USER" \
  -e "ssh_port=$TARGET_SSH_PORT" \
  -e "deploy_ssh_pub_key=$SSH_PUBLIC_KEY" \
  -e "app_domain=$APP_DOMAIN" \
  -e "app_www_domain=$APP_WWW_DOMAIN" \
  -e "zabbix_domain=$ZABBIX_DOMAIN" \
  -e "ssl_email=$SSL_EMAIL"

echo "======================================="
echo "SUKCES: serwer został przygotowany."
echo "Użytkownik deploy: $DEPLOY_USER"
echo "Szablon /opt/qresto/.env.bootstrap jest gotowy na VPS"
echo "Następny krok:"
echo "1) zaloguj się na VPS i skopiuj /opt/qresto/.env.bootstrap do /opt/qresto/.env"
echo "2) uzupełnij CF_DNS_API_TOKEN, TELEGRAM_BOT_TOKEN i TELEGRAM_CHAT_ID w pliku .env"
echo "3) zmień hasła CHANGE_ME_* w pliku .env"
echo "4) ustaw GitHub Secret VPS_SSH_USER=$DEPLOY_USER"
echo "5) ustaw GitHub Secret VPS_SSH_PORT=$TARGET_SSH_PORT"
