#!/usr/bin/env bash
set -euo pipefail

# --- Config (env-overridable) ---
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
NAME="${NAME:-mysql-source}"

# MySQL (source)
MYSQL_HOST="${MYSQL_HOST:-primary-mysql}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-test_user}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-test_pass}"

# Debezium connector
SERVER_ID="${SERVER_ID:-184001}"
TOPIC_PREFIX="${TOPIC_PREFIX:-primary}"
DATABASE="${DATABASE:-test_db}"
TABLES="${TABLES:-test_db.items}"
INCLUDE_SCHEMA_CHANGES="${INCLUDE_SCHEMA_CHANGES:-false}"
SNAPSHOT_MODE="${SNAPSHOT_MODE:-initial}"
SNAPSHOT_LOCKING_MODE="${SNAPSHOT_LOCKING_MODE:-}"   # optional

# Kafka as seen FROM THE CONNECT CONTAINER
KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-kafka:9092}"
HISTORY_TOPIC="${HISTORY_TOPIC:-schema-changes.test_db}"

# (Optional) container name for reachability checks to Kafka
CONTAINER="${CONTAINER:-}"

# --- Helpers ---
bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
fail(){ echo "❌ $*"; exit 1; }
warn(){ echo "⚠️  $*"; }
ok(){ echo "✔ $*"; }

# --- Preflight: Connect up ---
bold "➡️  Waiting for Kafka Connect at $CONNECT_URL ..."
for _ in $(seq 1 60); do curl -fsS "$CONNECT_URL/" >/dev/null && break || sleep 1; done
curl -fsS "$CONNECT_URL/" >/dev/null || fail "Connect not reachable at $CONNECT_URL"
ok "Connect REST is up"

# --- Plugin available? ---
PLUGINS="$(curl -fsS "$CONNECT_URL/connector-plugins")"
echo "$PLUGINS" | grep -q '"io\.debezium\.connector\.mysql\.MySqlConnector"' \
  || fail "Debezium MySQL plugin not found by worker"
ok "Debezium MySQL plugin is available"

# --- Optional: verify Kafka resolvability from INSIDE the Connect container ---
if [[ -n "$CONTAINER" ]]; then
  bold "🔎 Checking Kafka reachability from container '$CONTAINER'"
  HOST_PART="${KAFKA_BOOTSTRAP%:*}"
  PORT_PART="${KAFKA_BOOTSTRAP##*:}"
  # DNS resolution
  if ! docker exec -i "$CONTAINER" bash -lc "getent hosts '$HOST_PART' >/dev/null 2>&1 || nslookup '$HOST_PART' >/dev/null 2>&1"; then
    warn "Kafka host '$HOST_PART' is NOT resolvable from container '$CONTAINER'"
    warn "Use a network alias reachable from the container or set KAFKA_BOOTSTRAP correctly."
  else
    ok "Host '$HOST_PART' resolves in container"
  fi
  # TCP reachability (best-effort; may fail if SASL/SSL enforces handshake)
  if docker exec -i "$CONTAINER" bash -lc "bash -c '>/dev/tcp/$HOST_PART/$PORT_PART' " >/dev/null 2>&1; then
    ok "TCP $KAFKA_BOOTSTRAP reachable from container"
  else
    warn "TCP $KAFKA_BOOTSTRAP NOT reachable from container (network/ports?)."
  fi
fi

# --- Build connector config (fixes earlier jq overwrite bug) ---
if command -v jq >/dev/null 2>&1; then
  # Base config
  CONFIG_ONLY_JSON="$(env \
    MYSQL_HOST="$MYSQL_HOST" MYSQL_PORT="$MYSQL_PORT" MYSQL_USER="$MYSQL_USER" MYSQL_PASSWORD="$MYSQL_PASSWORD" \
    SERVER_ID="$SERVER_ID" TOPIC_PREFIX="$TOPIC_PREFIX" DATABASE="$DATABASE" TABLES="$TABLES" \
    INCLUDE_SCHEMA_CHANGES="$INCLUDE_SCHEMA_CHANGES" SNAPSHOT_MODE="$SNAPSHOT_MODE" \
    KAFKA_BOOTSTRAP="$KAFKA_BOOTSTRAP" HISTORY_TOPIC="$HISTORY_TOPIC" SNAPSHOT_LOCKING_MODE="$SNAPSHOT_LOCKING_MODE" \
    jq -n '{
      "connector.class": "io.debezium.connector.mysql.MySqlConnector",
      "tasks.max": "1",
      "database.hostname": env.MYSQL_HOST,
      "database.port": env.MYSQL_PORT,
      "database.user": env.MYSQL_USER,
      "database.password": env.MYSQL_PASSWORD,
      "database.server.id": env.SERVER_ID,
      "topic.prefix": env.TOPIC_PREFIX,
      "database.include.list": env.DATABASE,
      "table.include.list": env.TABLES,
      "include.schema.changes": env.INCLUDE_SCHEMA_CHANGES,
      "snapshot.mode": env.SNAPSHOT_MODE,
      "schema.history.internal.kafka.bootstrap.servers": env.KAFKA_BOOTSTRAP,
      "schema.history.internal.kafka.topic": env.HISTORY_TOPIC
    } | if (env.SNAPSHOT_LOCKING_MODE|length) > 0
        then . + {"snapshot.locking.mode": env.SNAPSHOT_LOCKING_MODE}
        else .
        end'
  )"
else
  # Fallback without jq
  CONFIG_ONLY_JSON="$(cat <<JSON
{
  "connector.class": "io.debezium.connector.mysql.MySqlConnector",
  "tasks.max": "1",
  "database.hostname": "$MYSQL_HOST",
  "database.port": "$MYSQL_PORT",
  "database.user": "$MYSQL_USER",
  "database.password": "$MYSQL_PASSWORD",
  "database.server.id": "$SERVER_ID",
  "topic.prefix": "$TOPIC_PREFIX",
  "database.include.list": "$DATABASE",
  "table.include.list": "$TABLES",
  "include.schema.changes": "$INCLUDE_SCHEMA_CHANGES",
  "snapshot.mode": "$SNAPSHOT_MODE",
  "schema.history.internal.kafka.bootstrap.servers": "$KAFKA_BOOTSTRAP",
  "schema.history.internal.kafka.topic": "$HISTORY_TOPIC"
  $( [[ -n "$SNAPSHOT_LOCKING_MODE" ]] && echo ", \"snapshot.locking.mode\": \"$SNAPSHOT_LOCKING_MODE\"" )
}
JSON
)"
fi

# Quick sanity: ensure bootstrap is non-empty
if [[ -z "${KAFKA_BOOTSTRAP// }" ]]; then
  fail "schema.history.internal.kafka.bootstrap.servers is empty (KAFKA_BOOTSTRAP not set)"
fi

# --- Create/Update connector ---
exists_code="$(curl -s -o /dev/null -w '%{http_code}' "$CONNECT_URL/connectors/$NAME")"
if [[ "$exists_code" == "200" ]]; then
  bold "➡️  Updating existing connector '$NAME'"
  TMP="$(mktemp)"
  code="$(curl -sS -o "$TMP" -w '%{http_code}' -X PUT -H 'Content-Type: application/json' \
    --data "$CONFIG_ONLY_JSON" "$CONNECT_URL/connectors/$NAME/config")"
  [[ "$code" == "200" || "$code" == "201" ]] || { echo "Response:"; cat "$TMP"; rm -f "$TMP"; fail "Update failed (HTTP $code)"; }
  rm -f "$TMP"
else
  bold "➡️  Creating connector '$NAME'"
  WRAPPED_JSON="$(printf '{"name":"%s","config":%s}' "$NAME" "$CONFIG_ONLY_JSON")"
  TMP="$(mktemp)"
  code="$(curl -sS -o "$TMP" -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    --data "$WRAPPED_JSON" "$CONNECT_URL/connectors")"
  [[ "$code" == "200" || "$code" == "201" ]] || { echo "Response:"; cat "$TMP"; rm -f "$TMP"; fail "Create failed (HTTP $code)"; }
  rm -f "$TMP"
fi
ok "Connector registered/updated"

# --- Wait for status and print helpful diagnostics ---
bold "➡️  Waiting for /connectors/$NAME/status ..."
for _ in $(seq 1 60); do
  s_code="$(curl -s -o /dev/null -w '%{http_code}' "$CONNECT_URL/connectors/$NAME/status" || true)"
  [[ "$s_code" == "200" ]] && break || sleep 1
done

STATUS="$(curl -fsS "$CONNECT_URL/connectors/$NAME/status")"
if command -v jq >/dev/null 2>&1; then echo "$STATUS" | jq .; else echo "$STATUS"; fi

if echo "$STATUS" | grep -q '"state"\s*:\s*"RUNNING"'; then
  ok "Connector state: RUNNING"
else
  warn "Connector not fully RUNNING"
fi

# --- If a task failed, surface root causes clearly ---
if echo "$STATUS" | grep -q '"state"\s*:\s*"FAILED"'; then
  TRACE="$(echo "$STATUS" | sed -n 's/.*"trace"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\n/\n/g' | sed 's/\\"/"/g')"
  echo "------ Task failure trace (decoded) ------"
  printf "%s\n" "$TRACE"
  echo "-----------------------------------------"

  if echo "$TRACE" | grep -q 'No resolvable bootstrap urls given in bootstrap.servers'; then
    echo
    warn "Detected Kafka bootstrap resolution problem."
    echo "• Check that KAFKA_BOOTSTRAP='$KAFKA_BOOTSTRAP' is reachable from inside the Connect container."
    echo "• Use the container network alias of your broker (e.g. 'kafka:9092'), not 'localhost:9092'."
    echo "• If you provided CONTAINER, the script already tested DNS/TCP above."
  fi
  exit 6
fi

