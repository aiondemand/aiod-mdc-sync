#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./check_sink_connector.sh [--container connect-sink] [--name mysql-sink]
#                             [--timeout 10] [--verbose] [--show-config]

CONTAINER="connect-sink"
CONNECTOR="mysql-sink"
TIMEOUT=10
VERBOSE=false
SHOW_CONFIG=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container) CONTAINER="$2"; shift 2;;
    --name)      CONNECTOR="$2"; shift 2;;
    --timeout)   TIMEOUT="$2"; shift 2;;
    --verbose)   VERBOSE=true; shift 1;;
    --show-config) SHOW_CONFIG=true; shift 1;;
    -h|--help)
      echo "Usage: $0 [--container connect-sink] [--name mysql-sink] [--timeout 10] [--verbose] [--show-config]"
      exit 0;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

# --- Helpers ---
color() { [[ -t 1 ]] && printf "\033[%sm%s\033[0m\n" "$1" "$2" || printf "%s\n" "$2"; }
ok()    { color "32" "✔ $1"; }
warn()  { color "33" "⚠ $1"; }
err()   { color "31" "✘ $1"; }

# --- 1) Is container running? ---
if ! docker ps --format '{{.Names}}' | grep -q -w "$CONTAINER"; then
  err "Container '$CONTAINER' is not running"; exit 2
fi
ok "Container '$CONTAINER' is running"

# --- 2) Is REST API alive? ---
REST_ALIVE=false
for i in $(seq 1 "$TIMEOUT"); do
  if docker exec -i "$CONTAINER" curl -fsS http://localhost:8083/ >/dev/null 2>&1; then
    REST_ALIVE=true; break
  fi
  sleep 1
done

if ! $REST_ALIVE; then
  err "Connect REST API not reachable in '$CONTAINER'"
  exit 3
fi
ok "Connect REST API reachable at http://localhost:8083/"

# --- 3) Is connector registered? ---
if ! docker exec -i "$CONTAINER" curl -fsS "http://localhost:8083/connectors/$CONNECTOR" >/dev/null 2>&1; then
  warn "Connector '$CONNECTOR' is not registered on this worker"
  exit 4
fi
ok "Connector '$CONNECTOR' is registered"

# --- 4) Check status ---
STATUS_JSON="$(docker exec -i "$CONTAINER" curl -fsS "http://localhost:8083/connectors/$CONNECTOR/status" || true)"
if [[ -z "$STATUS_JSON" ]]; then
  err "No status response for '$CONNECTOR'"
  exit 5
fi

[[ "$VERBOSE" == "true" && "$(command -v jq)" ]] && echo "$STATUS_JSON" | jq .

CONNECTOR_STATE="$(echo "$STATUS_JSON" | jq -r '.connector.state')"
TASK_STATE="$(echo "$STATUS_JSON" | jq -r '.tasks[0].state')"
TASK_TRACE="$(echo "$STATUS_JSON" | jq -r '.tasks[0].trace // empty')"

[[ "$CONNECTOR_STATE" == "RUNNING" ]] && ok "Connector state: RUNNING" || warn "Connector state: $CONNECTOR_STATE"
[[ "$TASK_STATE" == "RUNNING" ]] && ok "Task state: RUNNING" || warn "Task state: $TASK_STATE"

if [[ -n "$TASK_TRACE" && "$TASK_STATE" != "RUNNING" ]]; then
  echo "------ Task failure trace ------"
  echo "$TASK_TRACE"
  echo "--------------------------------"
fi

# --- 5) Optional: Show current config ---
if $SHOW_CONFIG; then
  echo "------ Connector configuration ------"
  CONFIG_JSON="$(docker exec -i "$CONTAINER" curl -fsS "http://localhost:8083/connectors/$CONNECTOR/config")"
  if command -v jq >/dev/null 2>&1; then
    echo "$CONFIG_JSON" | jq .
  else
    echo "$CONFIG_JSON"
  fi
  echo "-------------------------------------"
fi

echo "✅ Sanity check finished"

