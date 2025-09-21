#!/usr/bin/env bash
set -euo pipefail

# Debezium / Kafka Connect diagnostics & smoke tests
#
# Usage:
#   ./check_debezium_connect.sh
#     --container connect                         # REQUIRED: Kafka Connect / Debezium container name
#     [--kafka-container kafka]
#     [--bootstrap kafka:9092]                 # broker address as seen from containers
#     [--expect-plugin io.debezium.connector.mysql.MySqlConnector]
#     [--connector-name mysql-source]          # check this connector's status if present
#     [--show-config]                          # print running connector config (secrets redacted)
#     [--validate-running]                     # validate the running config against its plugin
#     [--diff-config ./mysql-source.json]      # diff expected vs running config (normalized)
#     [--validate-config ./mysql-source.json]  # validate config file against plugin
#     [--check-topics]                         # verify Connect internal topics via Kafka container
#     [--show-logs]                            # show recent ERROR/WARN from Connect logs
#     [--run-actions]                          # (optional) pause/resume/restart tests
#     [--verbose]
#
# Example:
#   ./check_debezium_connect.sh --container connect --connector-name mysql-source --show-config --validate-running

# ---------- Defaults ----------
CONTAINER=""
KAFKA_CONTAINER="kafka"
BOOTSTRAP="kafka:9092"
EXPECT_PLUGIN="io.debezium.connector.mysql.MySqlConnector"
CONNECTOR_NAME=""
VALIDATE_CONFIG=""
SHOW_CONFIG=false
VALIDATE_RUNNING=false
DIFF_CONFIG=""
CHECK_TOPICS=false
SHOW_LOGS=false
RUN_ACTIONS=false
VERBOSE=false
HTTP_TIMEOUT=5

# ---------- Arg parsing ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --container)         CONTAINER="$2"; shift 2;;
    --kafka-container)   KAFKA_CONTAINER="$2"; shift 2;;
    --bootstrap)         BOOTSTRAP="$2"; shift 2;;
    --expect-plugin)     EXPECT_PLUGIN="$2"; shift 2;;
    --connector-name)    CONNECTOR_NAME="$2"; shift 2;;
    --validate-config)   VALIDATE_CONFIG="$2"; shift 2;;
    --show-config)       SHOW_CONFIG=true; shift 1;;
    --validate-running)  VALIDATE_RUNNING=true; shift 1;;
    --diff-config)       DIFF_CONFIG="$2"; shift 2;;
    --check-topics)      CHECK_TOPICS=true; shift 1;;
    --show-logs)         SHOW_LOGS=true; shift 1;;
    --run-actions)       RUN_ACTIONS=true; shift 1;;
    --verbose)           VERBOSE=true; shift 1;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

if [[ -z "$CONTAINER" ]]; then
  echo "Error: --container is required" >&2
  exit 1
fi

# ---------- Pretty printer ----------
COLOR=true
[[ -t 1 ]] || COLOR=false
green(){ $COLOR && printf "\033[32m%s\033[0m\n" "$1" || printf "%s\n" "$1"; }
red(){   $COLOR && printf "\033[31m%s\033[0m\n" "$1" || printf "%s\n" "$1"; }
yellow(){ $COLOR && printf "\033[33m%s\033[0m\n" "$1" || printf "%s\n" "$1"; }
blue(){  $COLOR && printf "\033[34m%s\033[0m\n" "$1" || printf "%s\n" "$1"; }
hr(){ printf "%s\n" "----------------------------------------"; }

PASS_CNT=0; FAIL_CNT=0; WARN_CNT=0
pass(){ green "✔ $1"; ((PASS_CNT++)) || true; }
fail(){ red   "✘ $1"; ((FAIL_CNT++)) || true; }
warn(){ yellow "⚠ $1"; ((WARN_CNT++)) || true; }

# ---------- Helpers ----------
have_jq(){ command -v jq >/dev/null 2>&1; }
in_container(){ docker exec -i "$1" bash -lc "$2"; }
container_running(){ docker ps --format '{{.Names}}' | grep -q -w "$1"; }

# Run HTTP against Connect REST (inside the container)
http_in_connect(){
  local method="$1"; local path="$2"; local data="${3:-}"
  if [[ -n "$data" ]]; then
    docker exec -i "$CONTAINER" bash -lc '
      if command -v curl >/dev/null 2>&1; then
        curl -sS -m '"$HTTP_TIMEOUT"' -X '"$method"' -H "Content-Type: application/json" --data @- http://localhost:8083'"$path"';
      elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout='"$HTTP_TIMEOUT"' --header="Content-Type: application/json" --post-file=- http://localhost:8083'"$path"';
      else
        echo NO_HTTP_CLIENT;
      fi
    ' <<< "$data"
  else
    docker exec -i "$CONTAINER" bash -lc '
      if command -v curl >/dev/null 2>&1; then
        curl -sS -m '"$HTTP_TIMEOUT"' -X '"$method"' http://localhost:8083'"$path"';
      elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout='"$HTTP_TIMEOUT"' http://localhost:8083'"$path"';
      else
        echo NO_HTTP_CLIENT;
      fi
    '
  fi
}

detect_kafka_cli(){
  local topics=""; local consumer=""; local kcat=""
  if in_container "$KAFKA_CONTAINER" 'command -v kafka-topics.sh >/dev/null 2>&1'; then topics="kafka-topics.sh";
  elif in_container "$KAFKA_CONTAINER" 'command -v kafka-topics >/dev/null 2>&1'; then topics="kafka-topics"; fi
  if in_container "$KAFKA_CONTAINER" 'command -v kafka-console-consumer.sh >/dev/null 2>&1'; then consumer="kafka-console-consumer.sh";
  elif in_container "$KAFKA_CONTAINER" 'command -v kafka-console-consumer >/dev/null 2>&1'; then consumer="kafka-console-consumer"; fi
  if in_container "$KAFKA_CONTAINER" 'command -v kcat >/dev/null 2>&1'; then kcat="kcat";
  elif in_container "$KAFKA_CONTAINER" 'command -v kafkacat >/dev/null 2>&1'; then kcat="kafkacat"; fi
  echo "$topics|$consumer|$kcat"
}

# ---------- 0) Container liveness ----------
blue "🔎 Debezium Connect checks"
hr
if container_running "$CONTAINER"; then
  pass "Connect container '$CONTAINER' is running"
else
  fail "Connect container '$CONTAINER' is NOT running"; exit 2
fi

# ---------- 1) REST API reachable & version ----------
resp="$(http_in_connect GET '/')" || true
if [[ "$resp" == "NO_HTTP_CLIENT" ]]; then
  fail "Neither curl nor wget found in '$CONTAINER' to query REST API"; exit 2
fi
if [[ -n "$resp" ]] && echo "$resp" | grep -qi '"version"'; then
  have_jq && echo "$resp" | jq . || echo "$resp"
  pass "Connect REST API reachable at http://localhost:8083/"
else
  fail "Cannot reach Connect REST API in '$CONTAINER' (http://localhost:8083/)"; exit 2
fi

# ---------- 2) List connector plugins ----------
plugins="$(http_in_connect GET '/connector-plugins')" || true
if [[ -n "$plugins" ]] && echo "$plugins" | grep -q '^\s*\['; then
  if have_jq; then
    echo "$plugins" | jq -r '.[].class'
  else
    echo "$plugins"
  fi
  pass "Connector plugins endpoint returned successfully"
else
  fail "Failed to list connector plugins"; exit 2
fi
if [[ -n "$EXPECT_PLUGIN" ]]; then
  if echo "$plugins" | grep -q "\"class\"[[:space:]]*:[[:space:]]*\"$EXPECT_PLUGIN\""; then
    pass "Expected plugin present: $EXPECT_PLUGIN"
  else
    fail "Exp
