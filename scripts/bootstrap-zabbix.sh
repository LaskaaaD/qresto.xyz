#!/usr/bin/env bash
set -euo pipefail

# Bootstrap demo monitoringu Zabbix przez API.
# Tworzy hosta, podpina templatey, web scenarios, triggery i dashboardy.
#
# Wymaga:
# - .env z ROOT_DOMAIN/APP_DOMAIN/ZABBIX_DOMAIN/TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID
#         /ZABBIX_API_USER/ZABBIX_API_PASSWORD/ZABBIX_HOSTNAME
# - jq

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="/opt/qresto"
if [ ! -d "$APP_DIR" ]; then
  APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

cd "$APP_DIR"

if [ ! -f .env ]; then
  echo "[BŁĄD] Brak .env w $APP_DIR"
  exit 1
fi

# Odporny loader .env: usuwa BOM/CRLF i ignoruje linie, które nie są KEY=VALUE.
load_env_file() {
  local env_file="$1"

  while IFS= read -r line || [ -n "$line" ]; do
    # Usuń końcówkę CR (Windows)
    line="${line%$'\r'}"

    # Pomiń puste linie i komentarze
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    # Akceptuj tylko poprawne wpisy środowiskowe
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      export "$line"
    fi
  done < <(sed $'1s/^\xEF\xBB\xBF//' "$env_file")
}

load_env_file ".env"

if ! command -v jq >/dev/null 2>&1; then
  echo "[BŁĄD] Brak jq. Zainstaluj: sudo apt install -y jq"
  exit 1
fi

ZABBIX_API_URL="https://${ZABBIX_DOMAIN}/api_jsonrpc.php"
HEALTH_URL="https://${APP_DOMAIN}/health"
LIVE_URL="https://${APP_DOMAIN}/live"
READY_URL="https://${APP_DOMAIN}/ready"
HOST_NAME="${ZABBIX_HOSTNAME:-qresto-vps-agent}"

if [ -z "${ZABBIX_API_USER:-}" ] || [ -z "${ZABBIX_API_PASSWORD:-}" ]; then
  echo "[BŁĄD] Ustaw ZABBIX_API_USER i ZABBIX_API_PASSWORD w .env"
  exit 1
fi

# ── Auth ─────────────────────────────────────────────

AUTH_TOKEN=""
for i in $(seq 1 20); do
  AUTH_TOKEN="$(curl -s -X POST "$ZABBIX_API_URL" -H 'Content-Type: application/json-rpc' -d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"user.login\",
    \"params\": {
      \"username\": \"${ZABBIX_API_USER}\",
      \"password\": \"${ZABBIX_API_PASSWORD}\"
    },
    \"id\": 1
  }" | jq -r '.result // empty')"

  if [ -n "$AUTH_TOKEN" ] && [ "$AUTH_TOKEN" != "null" ]; then
    echo "[OK] Zalogowano do Zabbix API (proba $i)."
    break
  fi

  if [ "$i" -eq 20 ]; then
    echo "[BŁĄD] Nie udało się zalogować do Zabbix API po 20 próbach: $ZABBIX_API_URL"
    exit 1
  fi

  echo "[INFO] Zabbix API jeszcze niegotowe (proba $i/20), ponawiam za 10s..."
  sleep 10
done

api_call() {
  local method="$1"
  local params="$2"
  local response

  response="$(curl -s -X POST "$ZABBIX_API_URL" \
    -H 'Content-Type: application/json-rpc' \
    -d "{
      \"jsonrpc\": \"2.0\",
      \"method\": \"$method\",
      \"params\": $params,
      \"auth\": \"$AUTH_TOKEN\",
      \"id\": 1
    }")"

  if ! echo "$response" | jq -e . >/dev/null 2>&1; then
    echo "[BŁĄD] Niepoprawna odpowiedź JSON z API Zabbix dla metody '$method'." >&2
    echo "[BŁĄD] Surowa odpowiedź: $response" >&2
    return 1
  fi

  if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    echo "[BŁĄD] Zabbix API zwrócił błąd dla metody '$method':" >&2
    echo "$response" | jq -c '.error' >&2
    return 1
  fi

  echo "$response"
}

# ── Templates ────────────────────────────────────────

echo "--- Szukanie templateów ---"

LINUX_TEMPLATE_ID="$(api_call "template.get" '{"filter":{"host":["Linux by Zabbix agent active"]}}' | jq -r '.result[0].templateid // empty')"
DOCKER_TEMPLATE_ID="$(api_call "template.get" '{"filter":{"host":["Docker by Zabbix agent 2"]}}' | jq -r '.result[0].templateid // empty')"

if [ -z "$LINUX_TEMPLATE_ID" ]; then
  echo "[BŁĄD] Nie znaleziono template: Linux by Zabbix agent active"
  exit 1
fi

if [ -z "$DOCKER_TEMPLATE_ID" ]; then
  echo "[WARN] Nie znaleziono template: Docker by Zabbix agent 2 — monitoring kontenerów niedostępny"
fi

# ── Host ─────────────────────────────────────────────

echo "--- Konfiguracja hosta ---"

HOST_ID="$(api_call "host.get" "{\"filter\":{\"host\":[\"$HOST_NAME\"]}}" | jq -r '.result[0].hostid // empty')"

# Budujemy listę templateów do podpięcia
templates_json="[{\"templateid\": \"$LINUX_TEMPLATE_ID\"}"
[ -n "$DOCKER_TEMPLATE_ID" ] && templates_json+=",{\"templateid\": \"$DOCKER_TEMPLATE_ID\"}"
templates_json+="]"

if [ -z "$HOST_ID" ]; then
  echo "[INFO] Tworzenie hosta: $HOST_NAME"
  HOST_ID="$(api_call "host.create" "{
    \"host\": \"$HOST_NAME\",
    \"interfaces\": [{
      \"type\": 1,
      \"main\": 1,
      \"useip\": 0,
      \"dns\": \"zabbix-agent2\",
      \"ip\": \"\",
      \"port\": \"10050\"
    }],
    \"groups\": [{\"groupid\": \"2\"}],
    \"templates\": $templates_json
  }" | jq -r '.result.hostids[0] // empty')"
else
  echo "[INFO] Host '$HOST_NAME' istnieje (ID: $HOST_ID). Aktualizuję templatey..."
  # Podpięcie templateów (idempotentne — istniejące nie zostaną zduplikowane)
  api_call "host.update" "{
    \"hostid\": \"$HOST_ID\",
    \"templates\": $templates_json
  }" > /dev/null
fi

if [ -z "$HOST_ID" ]; then
  echo "[BŁĄD] Nie udało się utworzyć/odczytać hosta $HOST_NAME"
  exit 1
fi

echo "[OK] Host: $HOST_NAME (ID: $HOST_ID)"

# ── Web Scenarios ────────────────────────────────────

echo "--- Konfiguracja web scenarios ---"

create_web_scenario() {
  local scenario_name="$1"
  local step_name="$2"
  local url="$3"

  local existing
  existing="$(api_call "httptest.get" "{\"hostids\":\"$HOST_ID\",\"filter\":{\"name\":[\"$scenario_name\"]}}" | jq -r '.result[0].httptestid // empty')"

  if [ -z "$existing" ]; then
    api_call "httptest.create" "{
      \"name\": \"$scenario_name\",
      \"hostid\": \"$HOST_ID\",
      \"delay\": \"1m\",
      \"steps\": [{
        \"name\": \"$step_name\",
        \"url\": \"$url\",
        \"status_codes\": \"200\",
        \"no\": 1
      }]
    }" > /dev/null
    echo "[OK] Web scenario: $scenario_name → $url"
  else
    echo "[INFO] Web scenario '$scenario_name' już istnieje — pomijam."
  fi
}

create_web_scenario "QResto Health" "health" "$HEALTH_URL"
create_web_scenario "QResto Live"   "live"   "$LIVE_URL"
create_web_scenario "QResto Ready"  "ready"  "$READY_URL"

# ── Triggers ─────────────────────────────────────────

echo "--- Konfiguracja triggerów ---"

create_trigger() {
  local description="$1"
  local expression="$2"
  local priority="$3"

  local existing
  existing="$(api_call "trigger.get" "{\"filter\":{\"description\":[\"$description\"]}}" | jq -r '.result[0].triggerid // empty')"

  if [ -z "$existing" ]; then
    api_call "trigger.create" "{
      \"description\": \"$description\",
      \"expression\": \"$expression\",
      \"priority\": $priority
    }" > /dev/null
    echo "[OK] Trigger: $description"
  else
    echo "[INFO] Trigger '$description' już istnieje — pomijam."
  fi
}

create_trigger "QResto health check failed"               "last(/$HOST_NAME/web.test.fail[QResto Health])>0" 4
create_trigger "QResto liveness check failed"              "last(/$HOST_NAME/web.test.fail[QResto Live])>0"   3
create_trigger "QResto readiness check failed"             "last(/$HOST_NAME/web.test.fail[QResto Ready])>0"  3

# ── Cert item + trigger ──────────────────────────────

echo "--- Konfiguracja metryki certyfikatu ---"

cert_item_name="ACME cert days left"
cert_item_key="qresto.acme.days.left"
cert_item_id="$(api_call "item.get" "{\"hostids\":\"$HOST_ID\",\"filter\":{\"key_\":[\"$cert_item_key\"]}}" | jq -r '.result[0].itemid // empty')"
if [ -z "$cert_item_id" ]; then
  cert_item_id="$(api_call "item.create" "{
    \"name\": \"$cert_item_name\",
    \"key_\": \"$cert_item_key\",
    \"hostid\": \"$HOST_ID\",
    \"type\": 2,
    \"value_type\": 3,
    \"delay\": \"0\"
  }" | jq -r '.result.itemids[0] // empty')"
  echo "[OK] Item: $cert_item_name (key: $cert_item_key)"
else
  echo "[INFO] Item '$cert_item_name' (key: $cert_item_key) już istnieje — pomijam."
fi

create_trigger "ACME certificate expires in <20 days" "last(/$HOST_NAME/qresto.acme.days.left)<20" 4

# ── Telegram Media Type + Alert Action ──────────────

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  echo "--- Konfiguracja Telegram Media Type ---"

  telegram_mediatype_name="QResto Telegram"
  telegram_mediatypeid="$(api_call "mediatype.get" "{\"filter\":{\"name\":[\"$telegram_mediatype_name\"]}}" | jq -r '.result[0].mediatypeid // empty')"

  telegram_script="$(cat <<'JS'
var data = {};
if (typeof value === "string") {
  try {
    data = JSON.parse(value);
  } catch (e) {
    data = {};
  }
} else if (typeof value === "object" && value !== null) {
  data = value;
}

var rawToken = (data.TOKEN || data.token || data.api_token || "").toString().trim();
var rawChatId = (data.CHAT_ID || data.chat_id || data.api_chat_id || data.sendto || "").toString().trim();
var message = (data.MESSAGE || data.message || data.alert_message || "").toString();

rawToken = rawToken.replace(/^["']|["']$/g, "");
rawChatId = rawChatId.replace(/^["']|["']$/g, "");
rawToken = rawToken.replace(/[\u200B-\u200D\uFEFF]/g, "");
rawChatId = rawChatId.replace(/[\u200B-\u200D\uFEFF]/g, "");
rawToken = rawToken.replace(/\s+/g, "");
rawChatId = rawChatId.replace(/\s+/g, "");

if (rawToken.indexOf("https://api.telegram.org/") === 0) {
  var m = rawToken.match(/\/bot([^\/]+)\/sendMessage\/?$/);
  if (m && m[1]) {
    rawToken = m[1];
  }
}

if (rawToken.indexOf("bot") === 0) {
  rawToken = rawToken.substring(3);
}

if (rawChatId.length === 0) {
  throw "Missing Telegram chat id";
}
if (rawToken.length === 0) {
  throw "Missing Telegram bot token";
}

var params = {chat_id: rawChatId, text: message, parse_mode: "HTML"};
var req = new HttpRequest();
req.addHeader("Content-Type: application/json");
var resp = req.post("https://api.telegram.org/bot" + rawToken + "/sendMessage", JSON.stringify(params));
if (req.getStatus() != 200) {
  throw "HTTP " + req.getStatus() + ": " + resp;
}
return resp;
JS
)"

  if [ -z "$telegram_mediatypeid" ]; then
    telegram_mediatypeid="$(api_call "mediatype.create" "{
      \"name\": \"$telegram_mediatype_name\",
      \"type\": 4,
      \"status\": 0,
      \"script\": $(echo "$telegram_script" | jq -Rs .),
      \"timeout\": \"10s\",
      \"process_tags\": 0,
      \"parameters\": [
        {\"name\": \"TOKEN\",   \"value\": \"${TELEGRAM_BOT_TOKEN}\"},
        {\"name\": \"CHAT_ID\", \"value\": \"${TELEGRAM_CHAT_ID}\"},
        {\"name\": \"MESSAGE\", \"value\": \"{ALERT.MESSAGE}\"}
      ],
      \"message_templates\": [{
        \"eventsource\": 0,
        \"recovery\": 0,
        \"subject\": \"Problem: {EVENT.NAME}\",
        \"message\": \"[ALERT] {EVENT.NAME}\nHost: {HOST.NAME}\nSeverity: {EVENT.SEVERITY}\nTime: {EVENT.TIME} {EVENT.DATE}\nStatus: {EVENT.STATUS}\"
      },{
        \"eventsource\": 0,
        \"recovery\": 1,
        \"subject\": \"Resolved: {EVENT.NAME}\",
        \"message\": \"[OK] Resolved: {EVENT.NAME}\nHost: {HOST.NAME}\nTime: {EVENT.RECOVERY.TIME} {EVENT.RECOVERY.DATE}\"
      }]
    }" | jq -r '.result.mediatypeids[0] // empty')"

    if [ -n "$telegram_mediatypeid" ]; then
      echo "[OK] Telegram media type utworzony (ID: $telegram_mediatypeid)"
    else
      echo "[WARN] Nie udalo sie utworzyc Telegram media type"
    fi
  else
    echo "[INFO] Telegram media type juz istnieje (ID: $telegram_mediatypeid) - aktualizuje."
    api_call "mediatype.update" "{
      \"mediatypeid\": \"$telegram_mediatypeid\",
      \"status\": 0,
      \"script\": $(echo "$telegram_script" | jq -Rs .),
      \"timeout\": \"10s\",
      \"process_tags\": 0,
      \"parameters\": [
        {\"name\": \"TOKEN\",   \"value\": \"${TELEGRAM_BOT_TOKEN}\"},
        {\"name\": \"CHAT_ID\", \"value\": \"${TELEGRAM_CHAT_ID}\"},
        {\"name\": \"MESSAGE\", \"value\": \"{ALERT.MESSAGE}\"}
      ]
    }" > /dev/null
  fi

  # Przypisz media type do uzytkownika Admin (userid=1).
  if [ -n "$telegram_mediatypeid" ]; then
    existing_media="$(api_call "user.get" "{\"userids\":[\"1\"],\"selectMedias\":\"extend\"}" | jq -r ".result[0].medias // [] | map(select(.mediatypeid == \"$telegram_mediatypeid\")) | .[0].mediaid // empty")"
    if [ -z "$existing_media" ]; then
      api_call "user.update" "{
        \"userid\": \"1\",
        \"medias\": [{
          \"mediatypeid\": \"$telegram_mediatypeid\",
          \"sendto\": \"${TELEGRAM_CHAT_ID}\",
          \"active\": 0,
          \"severity\": 63,
          \"period\": \"1-7,00:00-24:00\"
        }]
      }" > /dev/null
      echo "[OK] Telegram przypisany do uzytkownika Admin"
    else
      echo "[INFO] Telegram juz przypisany do Admin - pomijam."
    fi
  fi

  echo "--- Konfiguracja Trigger Action ---"
  action_name="QResto - Alert Telegram"
  existing_action="$(api_call "action.get" '{"search":{"name":"Alert Telegram"}}' | jq -r --arg preferred "$action_name" '.result | if length == 0 then empty else (map(select(.name == $preferred))[0] // .[0]).actionid end')"
  custom_action_id="$existing_action"

  if [ -z "$existing_action" ]; then
    custom_action_id="$(api_call "action.create" "{
      \"name\": \"$action_name\",
      \"eventsource\": 0,
      \"status\": 0,
      \"filter\": {
        \"evaltype\": 0,
        \"conditions\": [{
          \"conditiontype\": 4,
          \"operator\": 5,
          \"value\": \"2\"
        }]
      },
      \"operations\": [{
        \"operationtype\": 0,
        \"opmessage\": {
          \"default_msg\": 1,
          \"mediatypeid\": \"$telegram_mediatypeid\"
        },
        \"opmessage_usr\": [{\"userid\": \"1\"}]
      }],
      \"recovery_operations\": [{
        \"operationtype\": 11,
        \"opmessage\": {\"default_msg\": 1}
      }]
    }" | jq -r '.result.actionids[0] // empty')"

    if [ -z "$custom_action_id" ]; then
      echo "[BLAD] action.create nie zwrocil actionid dla '$action_name'." >&2
      exit 1
    fi

    echo "[OK] Trigger action '$action_name' utworzona i aktywna (ID: $custom_action_id)"
  else
    api_call "action.update" "{
      \"actionid\": \"$existing_action\",
      \"status\": 0,
      \"filter\": {
        \"evaltype\": 0,
        \"conditions\": [{
          \"conditiontype\": 4,
          \"operator\": 5,
          \"value\": \"2\"
        }]
      },
      \"operations\": [{
        \"operationtype\": 0,
        \"opmessage\": {
          \"default_msg\": 1,
          \"mediatypeid\": \"$telegram_mediatypeid\"
        },
        \"opmessage_usr\": [{\"userid\": \"1\"}]
      }],
      \"recovery_operations\": [{
        \"operationtype\": 11,
        \"opmessage\": {\"default_msg\": 1}
      }]
    }" > /dev/null
    custom_action_id="$existing_action"
    echo "[INFO] Trigger action '$action_name' - upewniono sie, ze jest wlaczona (ID: $custom_action_id)"
  fi

  legacy_only_action_ids="$(api_call "action.get" '{"search":{"name":"Alert Telegram"}}' | jq -r --arg keep "$custom_action_id" '.result[] | select(.actionid != $keep) | .actionid')"
  if [ -n "$legacy_only_action_ids" ]; then
    while IFS= read -r legacy_id; do
      [ -z "$legacy_id" ] && continue
      if [ "$legacy_id" != "$custom_action_id" ]; then
        api_call "action.update" "{\"actionid\": \"$legacy_id\", \"status\": 1}" > /dev/null
        echo "[INFO] Wylaczono legacy akcje Telegram (ID: $legacy_id)"
      fi
    done <<< "$legacy_only_action_ids"
  fi

  default_action_id="$(api_call "action.get" '{"filter":{"name":["Report problems to Zabbix administrators"]}}' | jq -r '.result[0].actionid // empty')"
  if [ -n "$default_action_id" ] && [ -n "$custom_action_id" ]; then
    api_call "action.update" "{\"actionid\": \"$default_action_id\", \"status\": 1}" > /dev/null
    echo "[INFO] Domyslna akcja 'Report problems...' wylaczona (zastapiona przez QResto)"
  elif [ -n "$default_action_id" ]; then
    echo "[WARN] Custom action nie istnieje, domyslna akcja pozostaje aktywna."
  fi
else
  echo "[WARN] TELEGRAM_BOT_TOKEN lub TELEGRAM_CHAT_ID nie ustawione - pomijam konfiguracje alertow"
fi

# ── Dashboards ───────────────────────────────────────

echo "--- Tworzenie dashboardów ---"

DASHBOARDS_SCRIPT="$SCRIPT_DIR/bootstrap-dashboards.sh"

if [ -f "$DASHBOARDS_SCRIPT" ]; then
  export ZABBIX_API_URL AUTH_TOKEN HOST_ID HOST_NAME
  if ! bash "$DASHBOARDS_SCRIPT"; then
    echo "[BŁĄD] Nie udało się utworzyć dashboardów. Przerwano bootstrap Zabbix."
    echo "[INFO] Kolejna próba może zostać wykonana automatycznie przez cron."
    exit 1
  fi
else
  echo "[BŁĄD] Brak skryptu $DASHBOARDS_SCRIPT — nie można dokończyć bootstrapu Zabbix."
  exit 1
fi

# ── Podsumowanie ─────────────────────────────────────

echo ""
echo "======================================="
echo "[OK] Zabbix bootstrap zakończony:"
echo "  Host:       $HOST_NAME"
echo "  Templatey:  Linux by Zabbix agent active"
[ -n "$DOCKER_TEMPLATE_ID" ] && echo "              Docker by Zabbix agent 2"
echo "  Web:        /health, /live, /ready"
echo "  Triggery:   health fail, live fail, ready fail, cert <20 dni"
echo "  Dashboardy: patrz Zabbix Web → Monitoring → Dashboards"
echo "======================================="
