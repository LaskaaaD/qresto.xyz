#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "====== QResto VPS provisioning ======"

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "[ERROR] ansible-playbook was not found."
  echo "Install Ansible and run this script again."
  exit 1
fi

if command -v ansible-galaxy >/dev/null 2>&1; then
  ansible-galaxy collection install -r ansible/requirements.yml
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

escape_regex() {
  printf '%s' "$1" | sed -e 's/[.[\*^$()+?{}|]/\\&/g'
}

SERVER_IP=""
while [ -z "$SERVER_IP" ]; do
  read -r -p "VPS IP address: " SERVER_IP
  if [ -z "$SERVER_IP" ]; then
    echo "[ERROR] VPS IP address cannot be empty."
  fi
done

SSH_USER="$(prompt_default "Initial SSH user" "root")"
SSH_PORT="$(prompt_default "Initial SSH port" "22")"
if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
  echo "[ERROR] Invalid SSH port: $SSH_PORT"
  exit 1
fi

TARGET_SSH_PORT="$(prompt_default "Target SSH port after hardening" "$SSH_PORT")"
if [[ ! "$TARGET_SSH_PORT" =~ ^[0-9]+$ ]] || [ "$TARGET_SSH_PORT" -lt 1 ] || [ "$TARGET_SSH_PORT" -gt 65535 ]; then
  echo "[ERROR] Invalid target SSH port: $TARGET_SSH_PORT"
  exit 1
fi

SSH_PRIVATE_KEY="$(prompt_default "SSH private key path" "$HOME/.ssh/id_ed25519")"
if [ ! -f "$SSH_PRIVATE_KEY" ]; then
  echo "[ERROR] Private key not found: $SSH_PRIVATE_KEY"
  exit 1
fi

DEFAULT_PUB_KEY="$SSH_PRIVATE_KEY.pub"
if [ ! -f "$DEFAULT_PUB_KEY" ]; then
  DEFAULT_PUB_KEY="$HOME/.ssh/id_ed25519.pub"
fi

SSH_PUBLIC_KEY="$(prompt_default "Deploy user's SSH public key path" "$DEFAULT_PUB_KEY")"
if [ ! -f "$SSH_PUBLIC_KEY" ]; then
  echo "[ERROR] Public key not found: $SSH_PUBLIC_KEY"
  exit 1
fi

DEPLOY_USER="$(prompt_default "Deploy username" "qresto")"
if [[ ! "$DEPLOY_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "[ERROR] Invalid deploy username: $DEPLOY_USER"
  exit 1
fi

ROOT_DOMAIN=""
while [ -z "$ROOT_DOMAIN" ]; do
  read -r -p "Root domain, for example qresto.xyz: " ROOT_DOMAIN
  if [ -z "$ROOT_DOMAIN" ]; then
    echo "[ERROR] Root domain cannot be empty."
  fi
done

APP_DOMAIN="$(prompt_default "Application domain" "$ROOT_DOMAIN")"
APP_WWW_DOMAIN="$(prompt_default "WWW domain" "www.$ROOT_DOMAIN")"
ZABBIX_DOMAIN="$(prompt_default "Zabbix domain" "zabbix.$ROOT_DOMAIN")"
SSL_EMAIL="$(prompt_default "Let's Encrypt e-mail" "admin@$ROOT_DOMAIN")"
ROOT_DOMAIN_REGEX="$(escape_regex "$ROOT_DOMAIN")"

echo "[INFO] Writing ansible/inventory for $SERVER_IP"
{
  echo "[vps]"
  echo "target ansible_host=$SERVER_IP ansible_port=$SSH_PORT ansible_ssh_private_key_file=$SSH_PRIVATE_KEY"
} > ansible/inventory

echo "[INFO] Running Ansible provisioning..."
ansible-playbook -i ansible/inventory ansible/setup.yml \
  -e "ansible_user=$SSH_USER" \
  -e "ansible_become=yes" \
  -e "initial_ssh_port=$SSH_PORT" \
  -e "deploy_user=$DEPLOY_USER" \
  -e "ssh_port=$TARGET_SSH_PORT" \
  -e "deploy_ssh_pub_key=$SSH_PUBLIC_KEY" \
  -e "root_domain=$ROOT_DOMAIN" \
  -e "root_domain_regex=$ROOT_DOMAIN_REGEX" \
  -e "app_domain=$APP_DOMAIN" \
  -e "app_www_domain=$APP_WWW_DOMAIN" \
  -e "zabbix_domain=$ZABBIX_DOMAIN" \
  -e "ssl_email=$SSL_EMAIL"

echo "======================================="
echo "Success: the VPS baseline is ready."
echo "Deploy user: $DEPLOY_USER"
echo "Bootstrap template: /opt/qresto/.env.bootstrap"
echo
echo "Next steps:"
echo "1. SSH into the VPS as $DEPLOY_USER on port $TARGET_SSH_PORT."
echo "2. Copy /opt/qresto/.env.bootstrap to /opt/qresto/.env."
echo "3. Fill every placeholder secret in /opt/qresto/.env."
echo "4. Add GitHub Actions secrets: VPS_HOST, VPS_SSH_USER, VPS_SSH_KEY, VPS_SSH_PORT."
echo "5. Trigger the production deploy manually from GitHub Actions."
