#!/usr/bin/env bash
set -euo pipefail

# --- usage & args ---
if [ $# -ne 2 ]; then
  echo "Usage: $0 <topic_name> <kafka_container_name>"
  echo "Example: $0 dbserver1.inventory.items kafka"
  exit 1
fi
TOPIC_NAME="$1"
KAFKA_CONTAINER="$2"

# --- Check if kafka container is running ---
if ! docker ps --format '{{.Names}}' | grep -q "^$KAFKA_CONTAINER$"; then
    echo "Error: The '$KAFKA_CONTAINER' container is not running."
    echo "Please start the primary services first."
    exit 1
fi

echo "🔎 Checking for messages in Kafka topic: $TOPIC_NAME"
echo "   (Will wait for up to 10 seconds for messages...)"

# Execute the kafka-console-consumer inside the kafka container
# We use a timeout to avoid the script hanging forever if the topic is empty
MESSAGES=$(docker exec "$KAFKA_CONTAINER" kafka-console-consumer \
    --bootstrap-server localhost:9092 \
    --topic "$TOPIC_NAME" \
    --from-beginning \
    --timeout-ms 10000 2>/dev/null || true)

# --- Check results ---
if [ -n "$MESSAGES" ]; then
  echo "✅ Found messages in topic '$TOPIC_NAME':"
  echo "----------------------------------------"
  echo "$MESSAGES"
  echo "----------------------------------------"
  exit 0
else
  echo "❌ No messages found in topic '$TOPIC_NAME' within the timeout."
  echo "   - Ensure Debezium is running and connected."
  echo "   - Check that you have made changes to the source database."
  exit 1
fi
