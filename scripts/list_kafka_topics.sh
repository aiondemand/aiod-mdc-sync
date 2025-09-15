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

# Execute the kafka-topics.sh script inside the specified kafka container to list topics
docker exec "$KAFKA_CONTAINER_NAME" /opt/bitnami/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

echo "----------------------------------------"
echo "To inspect a specific topic, run:"
echo "  ./scripts/check_kafka_topic.sh <topic_name>"
