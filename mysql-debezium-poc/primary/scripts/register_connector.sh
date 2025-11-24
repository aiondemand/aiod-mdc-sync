#!/bin/bash

# Wait for Kafka Connect to be ready
echo "Waiting for Kafka Connect to start..."
MAX_WAIT=60
WAIT_COUNT=0
while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8083/) -ne 200 ]; do
  sleep 5
  WAIT_COUNT=$((WAIT_COUNT + 5))
  if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    echo "Timeout waiting for Kafka Connect to start"
    exit 1
  fi
done

echo "Kafka Connect is ready!"

# Wait a bit more to ensure Connect is fully initialized
sleep 10

# Check if connector already exists
echo "Checking if connector exists..."
CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/mysql-source-v2/status 2>/dev/null)

if echo "$CONNECTOR_STATUS" | grep -q "error_code"; then
  echo "Registering Debezium MySQL source connector..."
  RESPONSE=$(curl -s -X POST http://localhost:8083/connectors \
    -H "Content-Type: application/json" \
    -d @/tmp/connector.json)
  
  if echo "$RESPONSE" | grep -q "name"; then
    echo "Connector registered successfully!"
    echo "$RESPONSE" | python3 -m json.tool || echo "$RESPONSE"
  else
    echo "Failed to register connector:"
    echo "$RESPONSE"
  fi
else
  echo "Connector already exists, skipping registration."
  echo "$CONNECTOR_STATUS" | python3 -m json.tool || echo "$CONNECTOR_STATUS"
fi
