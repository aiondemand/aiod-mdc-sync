#!/usr/bin/env bash
set -euo pipefail

# --- Check if kafka container is running ---
if ! docker ps --format '{{.Names}}' | grep -q -w "kafka"; then
    echo "Error: The 'kafka' container is not running."
    echo "Please start the primary services first."
    exit 1
fi

echo "🔎 Listing all Kafka topics..."
echo "----------------------------------------"

# Execute the kafka-topics.sh script inside the kafka container to list topics
docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list

echo "----------------------------------------"
echo "To inspect a specific topic, run:"
echo "  ./scripts/check_kafka_topic.sh <topic_name>"
