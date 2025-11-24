#!/bin/bash
set -e

# Start Kafka Connect in the background
/docker-entrypoint.sh start &
CONNECT_PID=$!

# Register the connector in the background
/usr/local/bin/register_connector.sh &

# Wait for Kafka Connect process
wait $CONNECT_PID
