#!/usr/bin/env bash
set -euo pipefail

# List Kafka topics from inside a Kafka container (portable across images).
# Usage:
#   ./list_kafka_topics.sh [--container kafka] [--bootstrap localhost:9092]
#                          [--filter REGEX] [--describe] [--include-internal]
#
# Examples:
#   ./list_kafka_topics.sh --container primary-kafka-1
#   ./list_kafka_topics.sh --container primary-kafka-1 --bootstrap kafka:9092
#   ./list_kafka_topics.sh --filter '^dbserver1\.'                 # only Debezium topics for server "dbserver1"
#   ./list_kafka_topics.sh --describe                              # show partitions/replicas
#
# Notes:
# - --bootstrap is the address as seen *inside* the container (often localhost:9092 or kafka:9092).
# - By default internal topics are excluded; add --include-internal to see __consumer_offsets, etc.

# Defaults
KAFKA_CONTAINER_NAME="kafka"
BOOTSTRAP="localhost:9092"
FILTER_REGEX=""
DO_DESCRIBE=false
INCLUDE_INTERNAL=false

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --container) KAFKA_CONTAINER_NAME="$2"; shift 2;;
    --bootstrap) BOOTSTRAP="$2"; shift 2;;
    --filter) FILTER_REGEX="$2"; shift 2;;
    --describe) DO_DESCRIBE=true; shift 1;;
    --include-internal) INCLUDE_INTERNAL=true; shift 1;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'; exit 0;;
    *)
      echo "Unknown option: $1"; exit 1;;
  esac
done

# Ensure container is running
if ! docker ps --format '{{.Names}}' | grep -q -w "$KAFKA_CONTAINER_NAME"; then
  echo "Error: The container '$KAFKA_CONTAINER_NAME' is not running."
  exit 1
fi

# Detect kafka-topics command inside the container
detect_topics_cli() {
  if docker exec "$KAFKA_CONTAINER_NAME" bash -lc 'command -v kafka-topics.sh >/dev/null 2>&1'; then
    echo "kafka-topics.sh"
  elif docker exec "$KAFKA_CONTAINER_NAME" bash -lc 'command -v kafka-topics >/dev/null 2>&1'; then
    echo "kafka-topics"
  else
    echo ""
  fi
}

TOPICS_CLI="$(detect_topics_cli)"
if [[ -z "$TOPICS_CLI" ]]; then
  echo "Error: kafka-topics(.sh) not found in container '$KAFKA_CONTAINER_NAME'."
  echo "Try opening a shell to inspect PATH:"
  echo "  docker exec -it $KAFKA_CONTAINER_NAME bash"
  exit 1
fi

LIST_ARGS=( "--bootstrap-server" "$BOOTSTRAP" "--list" )
$INCLUDE_INTERNAL || LIST_ARGS+=( "--exclude-internal" )

echo "🔎 Listing Kafka topics from '$KAFKA_CONTAINER_NAME' (bootstrap: $BOOTSTRAP)"
echo "----------------------------------------"

# List topics
set +e
RAW_TOPICS="$(docker exec "$KAFKA_CONTAINER_NAME" bash -lc "$TOPICS_CLI ${LIST_ARGS[*]}")"
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]]; then
  echo "Failed to list topics (exit $STATUS). Check bootstrap address and broker health."
  exit $STATUS
fi

# Optionally filter
if [[ -n "$FILTER_REGEX" ]]; then
  TOPICS="$(echo "$RAW_TOPICS" | grep -E "$FILTER_REGEX" || true)"
else
  TOPICS="$RAW_TOPICS"
fi

if [[ -z "${TOPICS//[$'\t\r\n ']/}" ]]; then
  echo "No topics found${FILTER_REGEX:+ matching /$FILTER_REGEX/}."
  echo "Tips:"
  echo "  • Verify Debezium connector is running and producing."
  echo "  • Try --include-internal to ensure the broker is reachable."
  echo "  • If using Docker compose networking, your bootstrap may be 'kafka:9092'."
  exit 0
fi

# Print topics
echo "$TOPICS" | awk '{print " •",$0}'

# Optionally describe
if $DO_DESCRIBE; then
  echo "----------------------------------------"
  echo "📋 Describing topics..."
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    docker exec "$KAFKA_CONTAINER_NAME" bash -lc "$TOPICS_CLI --bootstrap-server $BOOTSTRAP --describe --topic \"$t\""
    echo
  done <<< "$TOPICS"
fi

echo "----------------------------------------"
echo "To inspect a topic's messages:"
echo "  ./scripts/check_kafka_topic.sh <topic_name> [--container $KAFKA_CONTAINER_NAME] [--bootstrap $BOOTSTRAP]"

