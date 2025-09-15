#!/usr/bin/env bash
set -euo pipefail

# --- Set container name ---
KAFKA_CONTAINER_NAME="${1:-kafka}" # Default to 'kafka' if no argument is provided

# --- Check if kafka container is running ---
if ! docker ps --format '{{.Names}}' | grep -q -w "$KAFKA_CONTAINER_NAME"; then
    echo "Error: The container '$KAFKA_CONTAINER_NAME' is not running."
    echo "Please ensure the Kafka container is started."
    exit 1
fi

echo "🔎 Listing all Kafka topics from container '$KAFKA_CONTAINER_NAME'..."
echo "----------------------------------------"

# Figure out the correct command inside container
if docker exec "$KAFKA_CONTAINER_NAME" bash -lc 'command -v kafka-topics.sh >/dev/null 2>&1'; then
    KAFKA_TOPICS_CMD="kafka-topics.sh"
elif docker exec "$KAFKA_CONTAINER_NAME" bash -lc 'command -v kafka-topics >/dev/null 2>&1'; then
    KAFKA_TOPICS_CMD="kafka-topics"
else
    echo "Error: kafka-topics(.sh) command not found in container '$KAFKA_CONTAINER_NAME'."
    exit 1
fi

# Execute inside container
docker exec "$KAFKA_CONTAINER_NAME" bash -lc "$KAFKA_TOPICS_CMD --bootstrap-server localhost:9092 --list"

echo "----------------------------------------"
echo "To inspect a specific topic, run:"
echo "  ./scripts/check_kafka_topic.sh <topic_name>"
