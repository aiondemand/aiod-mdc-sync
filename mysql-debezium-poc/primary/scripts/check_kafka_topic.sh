#!/usr/bin/env bash
set -euo pipefail

# Consume messages from a Kafka topic inside a Kafka container.
# Usage:
#   ./check_kafka_topic.sh <topic_name>
#       [--container kafka] [--bootstrap kafka:9092]
#       [--from-beginning] [--timeout 20] [--max-messages 0]
#       [--print-keys] [--raw] [--output file]
#
# Examples:
#   ./check_kafka_topic.sh primary.test_db.items --container db-kafka --bootstrap kafka:9092 --from-beginning
#   ./check_kafka_topic.sh connect-status --container db-kafka --from-beginning --raw --output dump.jsonl

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <topic_name> [--container kafka] [--bootstrap kafka:9092] [--from-beginning] [--timeout 20] [--max-messages 0] [--print-keys] [--raw] [--output file]"
  exit 1
fi

TOPIC="$1"; shift

# Defaults
KAFKA_CONTAINER_NAME="kafka"
BOOTSTRAP="kafka:9092"           # default internal broker name
FROM_BEGINNING=false
TIMEOUT_SEC=20
MAX_MESSAGES=0                   # 0 = unlimited (until timeout)
PRINT_KEYS=false
RAW=false
OUTPUT_FILE=""

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --container) KAFKA_CONTAINER_NAME="$2"; shift 2;;
    --bootstrap) BOOTSTRAP="$2"; shift 2;;
    --from-beginning) FROM_BEGINNING=true; shift 1;;
    --timeout) TIMEOUT_SEC="$2"; shift 2;;
    --max-messages) MAX_MESSAGES="$2"; shift 2;;
    --print-keys) PRINT_KEYS=true; shift 1;;
    --raw) RAW=true; shift 1;;
    --output) OUTPUT_FILE="$2"; shift 2;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'; exit 0;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

# Ensure container is running
if ! docker ps --format '{{.Names}}' | grep -q -w "$KAFKA_CONTAINER_NAME"; then
  echo "Error: The container '$KAFKA_CONTAINER_NAME' is not running."
  exit 1
fi

# Detect consumer CLI inside container
detect_consumer() {
  if docker exec "$KAFKA_CONTAINER_NAME" bash -lc 'command -v kafka-console-consumer.sh >/dev/null 2>&1'; then
    echo "kafka-console-consumer.sh"
  elif docker exec "$KAFKA_CONTAINER_NAME" bash -lc 'command -v kafka-console-consumer >/dev/null 2>&1'; then
    echo "kafka-console-consumer"
  elif docker exec "$KAFKA_CONTAINER_NAME" bash -lc 'command -v kcat >/dev/null 2>&1'; then
    echo "kcat"
  elif docker exec "$KAFKA_CONTAINER_NAME" bash -lc 'command -v kafkacat >/dev/null 2>&1'; then
    echo "kafkacat"
  else
    echo ""
  fi
}

CONSUMER_CLI="$(detect_consumer)"
if [[ -z "$CONSUMER_CLI" ]]; then
  echo "Error: No Kafka consumer tool found in container '$KAFKA_CONTAINER_NAME' (kafka-console-consumer(.sh) / kcat / kafkacat)."
  exit 1
fi

echo "🔎 Consuming from '$TOPIC' in '$KAFKA_CONTAINER_NAME' (bootstrap: $BOOTSTRAP)"
echo "    from-beginning: $FROM_BEGINNING, timeout: ${TIMEOUT_SEC}s, max-messages: ${MAX_MESSAGES}"
echo "    using: $CONSUMER_CLI"
[[ -n "$OUTPUT_FILE" ]] && echo "    output: $OUTPUT_FILE"
echo "----------------------------------------"

# Build the consumer command (runs in the container)
set +e
if [[ "$CONSUMER_CLI" == kafka-console-consumer* ]]; then
  # kafka-console-consumer path
  ARGS=( "--bootstrap-server" "$BOOTSTRAP" "--topic" "$TOPIC" "--timeout-ms" "$(( TIMEOUT_SEC * 1000 ))" )
  $FROM_BEGINNING && ARGS+=( "--from-beginning" )
  if $PRINT_KEYS; then
    ARGS+=( "--property" "print.key=true" "--property" "key.separator=|" )
  fi
  [[ "$MAX_MESSAGES" -gt 0 ]] && ARGS+=( "--max-messages" "$MAX_MESSAGES" )
  DOCKER_CMD=( docker exec -i "$KAFKA_CONTAINER_NAME" bash -lc "$CONSUMER_CLI ${ARGS[*]}" )
else
  # kcat / kafkacat path
  KCAT="$CONSUMER_CLI"
  KARGS=( "-C" "-b" "$BOOTSTRAP" "-t" "$TOPIC" "-q" "-e" )
  $FROM_BEGINNING && KARGS+=( "-o" "beginning" )
  [[ "$MAX_MESSAGES" -gt 0 ]] && KARGS+=( "-c" "$MAX_MESSAGES" )
  $PRINT_KEYS && KARGS+=( "-K" "|" )
  DOCKER_CMD=( docker exec -i "$KAFKA_CONTAINER_NAME" bash -lc "$KCAT ${KARGS[*]}" )
fi

# Host-side processing: RAW vs JSON-safe
run_and_pipe() {
  if $RAW; then
    # No parsing; optionally tee to file
    if [[ -n "$OUTPUT_FILE" ]]; then
      "${DOCKER_CMD[@]}" | tee "$OUTPUT_FILE"
    else
      "${DOCKER_CMD[@]}"
    fi
  else
    if command -v jq >/dev/null 2>&1; then
      # If keys are printed with a "|" delimiter, keep only the value part before JSON parsing.
      if $PRINT_KEYS; then
        # Split on first "|" to get the value, then parse JSON safely.
        JQ_FILTER='( . | split("|") ) as $p | ( if ($p|length>=2) then $p[1] else . end ) | fromjson? | select(.)'
      else
        JQ_FILTER='fromjson? | select(.)'
      fi
      if [[ -n "$OUTPUT_FILE" ]]; then
        "${DOCKER_CMD[@]}" | jq -Rr "$JQ_FILTER" | tee "$OUTPUT_FILE"
      else
        "${DOCKER_CMD[@]}" | jq -Rr "$JQ_FILTER"
      fi
    else
      echo "(jq not found on host; showing raw lines)"
      if [[ -n "$OUTPUT_FILE" ]]; then
        "${DOCKER_CMD[@]}" | tee "$OUTPUT_FILE"
      else
        "${DOCKER_CMD[@]}"
      fi
    fi
  fi
}

run_and_pipe
STATUS=$?
set -e

echo "----------------------------------------"
if [[ $STATUS -eq 0 || $STATUS -eq 124 ]]; then
  echo "Done."
else
  echo "Consumer exited with status $STATUS"
fi
