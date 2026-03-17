#!/usr/bin/env bash
set -euo pipefail

# Tworzy/aktualizuje 3 dashboardy Zabbix przez API.
# Tryb praktyczny: dashboardy maj powsta zawsze (minimum: problemy + kafle),
# a dodatkowe grafy Docker s dodawane jeli ju istniej.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="/opt/qresto"
if [ ! -d "$APP_DIR" ]; then
  APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

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

if ! command -v jq >/dev/null 2>&1; then
  echo "[BD] Brak jq. Zainstaluj: sudo apt install -y jq"
  exit 1
fi

# Standalone mode: pozwala uruchomic skrypt bezposrednio.
if [ -z "${ZABBIX_API_URL:-}" ] || [ -z "${AUTH_TOKEN:-}" ] || [ -z "${HOST_ID:-}" ] || [ -z "${HOST_NAME:-}" ]; then
  load_env_file "$APP_DIR/.env"

  if [ -z "${ZABBIX_API_URL:-}" ] && [ -n "${ZABBIX_DOMAIN:-}" ]; then
    ZABBIX_API_URL="https://${ZABBIX_DOMAIN}/api_jsonrpc.php"
  fi

  if [ -z "${HOST_NAME:-}" ] && [ -n "${ZABBIX_HOSTNAME:-}" ]; then
    HOST_NAME="${ZABBIX_HOSTNAME}"
  fi

  if [ -z "${ZABBIX_API_URL:-}" ] || [ -z "${ZABBIX_API_USER:-}" ] || [ -z "${ZABBIX_API_PASSWORD:-}" ] || [ -z "${HOST_NAME:-}" ]; then
    echo "[BD] Brak wymaganych danych. Ustaw: ZABBIX_API_URL, ZABBIX_API_USER, ZABBIX_API_PASSWORD, HOST_NAME (lub ZABBIX_HOSTNAME)."
    exit 1
  fi

  if [ -z "${AUTH_TOKEN:-}" ]; then
    AUTH_TOKEN="$(curl -s -X POST "$ZABBIX_API_URL" -H 'Content-Type: application/json-rpc' -d "{
      \"jsonrpc\":\"2.0\",
      \"method\":\"user.login\",
      \"params\":{\"username\":\"${ZABBIX_API_USER}\",\"password\":\"${ZABBIX_API_PASSWORD}\"},
      \"id\":1
    }" | jq -r '.result // empty')"
  fi

  if [ -z "${AUTH_TOKEN:-}" ]; then
    echo "[BD] Nie udalo sie zalogowac do Zabbix API: $ZABBIX_API_URL"
    exit 1
  fi

  if [ -z "${HOST_ID:-}" ]; then
    HOST_ID="$(curl -s -X POST "$ZABBIX_API_URL" -H 'Content-Type: application/json-rpc' -d "{
      \"jsonrpc\":\"2.0\",
      \"method\":\"host.get\",
      \"params\":{\"filter\":{\"host\":[\"$HOST_NAME\"]}},
      \"auth\":\"$AUTH_TOKEN\",
      \"id\":1
    }" | jq -r '.result[0].hostid // empty')"
  fi

  if [ -z "${HOST_ID:-}" ]; then
    echo "[BD] Nie znaleziono hosta '$HOST_NAME' w Zabbix."
    exit 1
  fi
fi

api_call() {
  local method="$1"
  local params="$2"
  local response

  response="$(curl -s -X POST "$ZABBIX_API_URL" \
    -H 'Content-Type: application/json-rpc' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"auth\":\"$AUTH_TOKEN\",\"id\":1}")"

  if ! echo "$response" | jq -e . >/dev/null 2>&1; then
    echo "[BD] Niepoprawna odpowiedz JSON z API dla metody '$method'." >&2
    echo "[BD] Surowa odpowiedz: $response" >&2
    return 1
  fi

  if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    echo "[BD] Zabbix API error dla metody '$method':" >&2
    echo "$response" | jq -c '.error' >&2
    return 1
  fi

  echo "$response"
}

get_dashboard_id() {
  api_call "dashboard.get" "{\"filter\":{\"name\":[\"$1\"]}}" | jq -r '.result[0].dashboardid // empty'
}

delete_if_exists() {
  local did
  did="$(get_dashboard_id "$1")"
  if [ -n "$did" ]; then
    api_call "dashboard.delete" "[\"$did\"]" > /dev/null
    echo "[INFO] Usunito stary dashboard '$1' — zostanie odtworzony."
  fi
}

find_graph() {
  local name="$1"
  api_call "graph.get" "{
    \"hostids\": \"$HOST_ID\",
    \"search\": {\"name\": \"$name\"},
    \"searchWildcardsEnabled\": true,
    \"limit\": 1
  }" | jq -r '.result[0].graphid // empty'
}

find_item() {
  local key="$1"
  api_call "item.get" "{
    \"hostids\": \"$HOST_ID\",
    \"search\": {\"key_\": \"$key\"},
    \"searchWildcardsEnabled\": true,
    \"webitems\": true,
    \"limit\": 1
  }" | jq -r '.result[0].itemid // empty'
}

get_docker_graphs_json() {
  local base_query='{
    "hostids": "'"$HOST_ID"'",
    "search": {"name": "Docker"},
    "searchWildcardsEnabled": true,
    "sortfield": "name",
    "output": ["graphid","name"]
  }'

  local q1 q2 q3 q4
  q1="$(api_call "graph.get" "$base_query" | jq -c '.result // []')"
  q2="$(api_call "graph.get" "$(echo "$base_query" | jq '. + {inherited: true}')" | jq -c '.result // []')"
  q3="$(api_call "graph.get" "$(echo "$base_query" | jq '. + {templated: true}')" | jq -c '.result // []')"
  q4="$(api_call "graph.get" "$(echo "$base_query" | jq '. + {inherited: true, templated: true}')" | jq -c '.result // []')"

  jq -c -n --argjson a "$q1" --argjson b "$q2" --argjson c "$q3" --argjson d "$q4" '
    ($a + $b + $c + $d)
    | unique_by(.graphid)
    | sort_by(.name)
  '
}

graph_widget() {
  local name="$1" x="$2" y="$3" w="$4" h="$5" graphid="$6"
  cat <<JSON
{
  "type": "graph",
  "name": "$name",
  "x": $x, "y": $y, "width": $w, "height": $h,
  "fields": [
    {"type": 0, "name": "graphid", "value": $graphid},
    {"type": 0, "name": "source_type", "value": 0}
  ]
}
JSON
}

item_widget() {
  local name="$1" x="$2" y="$3" w="$4" h="$5" itemid="$6"
  cat <<JSON
{
  "type": "item",
  "name": "$name",
  "x": $x, "y": $y, "width": $w, "height": $h,
  "fields": [
    {"type": 4, "name": "itemid.0", "value": "$itemid"},
    {"type": 0, "name": "show.0", "value": 1},
    {"type": 0, "name": "show.1", "value": 2}
  ]
}
JSON
}

problems_widget() {
  local name="$1" x="$2" y="$3" w="$4" h="$5"
  cat <<JSON
{
  "type": "problems",
  "name": "$name",
  "x": $x, "y": $y, "width": $w, "height": $h,
  "fields": [
    {"type": 3, "name": "hostids.0", "value": "$HOST_ID"}
  ]
}
JSON
}

create_dashboard() {
  local name="$1"
  local widgets_json="$2"
  api_call "dashboard.create" "{
    \"name\": \"$name\",
    \"display_period\": 30,
    \"auto_start\": 1,
    \"pages\": [{\"widgets\": $widgets_json}]
  }" > /dev/null
  echo "[OK] Utworzono dashboard: $name"
}

create_docker_dashboard() {
  local dash_name="QResto — Kontenery Docker"
  local item_running item_stopped item_ping
  item_running="$(find_item "docker.containers.running*")"
  item_stopped="$(find_item "docker.containers.stopped*")"
  item_ping="$(find_item "docker.ping*")"

  delete_if_exists "$dash_name"

  local widgets="["
  local sep=""
  add() { widgets+="${sep}$1"; sep=","; }

  add "$(problems_widget "Aktywne problemy" 0 0 36 4)"

  if [ -n "$item_running" ]; then
    add "$(item_widget "Kontenery uruchomione" 0 4 12 3 "$item_running")"
  fi
  if [ -n "$item_stopped" ]; then
    add "$(item_widget "Kontenery zatrzymane" 12 4 12 3 "$item_stopped")"
  fi
  if [ -n "$item_ping" ]; then
    add "$(item_widget "Docker Engine" 24 4 12 3 "$item_ping")"
  fi

  local graphs_json graph_count row
  graphs_json="$(get_docker_graphs_json)"
  graph_count="$(echo "$graphs_json" | jq 'length')"
  row=7

  if [ "$graph_count" -gt 0 ]; then
    while IFS= read -r graph_entry; do
      local gid gname
      gid="$(echo "$graph_entry" | jq -r '.graphid')"
      gname="$(echo "$graph_entry" | jq -r '.name')"
      if [ -n "$gid" ]; then
        add "$(graph_widget "$gname" 0 "$row" 36 5 "$gid")"
        row=$((row + 5))
      fi
    done < <(echo "$graphs_json" | jq -c '.[]')
    echo "[INFO] Dodano $graph_count grafów Docker."
  else
    echo "[WARN] Brak grafów Docker na tym etapie — dashboard pozostaje w wersji podstawowej."
  fi

  widgets+="]"
  create_dashboard "$dash_name" "$widgets"
}

create_server_dashboard() {
  local dash_name="QResto — Serwer VPS"
  delete_if_exists "$dash_name"

  local graph_cpu graph_mem graph_net graph_disk
  graph_cpu="$(find_graph "*CPU*")"
  graph_mem="$(find_graph "*Memory*")"
  graph_net="$(find_graph "*Network*")"
  graph_disk="$(find_graph "*Disk*")"

  local item_uptime item_disk item_swap
  item_uptime="$(find_item "system.uptime*")"
  item_disk="$(find_item "vfs.fs.size[/,pused*")"
  item_swap="$(find_item "system.swap.size[,pused*")"

  local widgets="["
  local sep=""
  add() { widgets+="${sep}$1"; sep=","; }

  if [ -n "$item_uptime" ]; then add "$(item_widget "Uptime serwera" 0 0 12 3 "$item_uptime")"; fi
  if [ -n "$item_disk" ]; then add "$(item_widget "Dysk / (%)" 12 0 12 3 "$item_disk")"; fi
  if [ -n "$item_swap" ]; then add "$(item_widget "SWAP (%)" 24 0 12 3 "$item_swap")"; fi

  local row=3
  if [ -n "$graph_cpu" ]; then add "$(graph_widget "CPU" 0 $row 36 5 "$graph_cpu")"; row=$((row + 5)); fi
  if [ -n "$graph_mem" ]; then add "$(graph_widget "Pami (RAM + Swap)" 0 $row 36 5 "$graph_mem")"; row=$((row + 5)); fi
  if [ -n "$graph_net" ]; then add "$(graph_widget "Ruch sieciowy" 0 $row 36 5 "$graph_net")"; row=$((row + 5)); fi
  if [ -n "$graph_disk" ]; then add "$(graph_widget "Operacje dyskowe" 0 $row 36 5 "$graph_disk")"; fi

  if [ -z "$item_uptime" ] && [ -z "$graph_cpu" ]; then
    add "$(problems_widget "Aktywne problemy" 0 3 36 6)"
    echo "[WARN] Dashboard VPS utworzony w wersji minimalnej (brak penych metryk)."
  fi

  widgets+="]"
  create_dashboard "$dash_name" "$widgets"
}

create_http_dashboard() {
  local dash_name="QResto — Aplikacja HTTP"
  delete_if_exists "$dash_name"

  local item_health_fail item_health_time item_live_time item_ready_time item_cert
  item_health_fail="$(find_item "web.test.fail[QResto Health]")"
  item_health_time="$(find_item "web.test.time[QResto Health*")"
  item_live_time="$(find_item "web.test.time[QResto Live*")"
  item_ready_time="$(find_item "web.test.time[QResto Ready*")"
  item_cert="$(find_item "qresto.acme.days.left*")"

  local widgets="["
  local sep=""
  add() { widgets+="${sep}$1"; sep=","; }

  if [ -n "$item_health_fail" ]; then
    add "$(item_widget "Health status (0=OK)" 0 0 12 3 "$item_health_fail")"
  fi
  if [ -n "$item_cert" ]; then
    add "$(item_widget "Certyfikat (dni)" 12 0 12 3 "$item_cert")"
  fi
  add "$(problems_widget "Problemy" 24 0 12 3)"

  if [ -n "$item_health_time" ]; then add "$(item_widget "/health czas odpowiedzi" 0 3 12 3 "$item_health_time")"; fi
  if [ -n "$item_live_time" ]; then add "$(item_widget "/live czas odpowiedzi" 12 3 12 3 "$item_live_time")"; fi
  if [ -n "$item_ready_time" ]; then add "$(item_widget "/ready czas odpowiedzi" 24 3 12 3 "$item_ready_time")"; fi

  widgets+="]"
  create_dashboard "$dash_name" "$widgets"
}

echo "=== Bootstrap dashboardów Zabbix ==="
create_docker_dashboard || true
create_server_dashboard || true
create_http_dashboard || true

echo "[OK] Dashboard bootstrap zakoczony (tryb podstawowy)."
exit 0
