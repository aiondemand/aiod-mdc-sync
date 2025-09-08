#!/bin/bash

echo "Verifying Debezium PoC Setup..."
echo "==============================="

# Check Docker and Docker Compose
echo "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed!"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose is not installed!"
    exit 1
fi

# Check environment files
echo -e "\nChecking environment files..."
if [ -f "../primary/.env" ]; then
    echo "PRIMARY .env file exists"
    # Check for required variables
    if grep -q "PRIMARY_PUB_IP" "../primary/.env"; then
        echo "PRIMARY_PUB_IP is configured"
    else
        echo "WARNING: PRIMARY_PUB_IP not found in primary/.env"
    fi
else
    echo "WARNING: primary/.env file not found"
fi

if [ -f "../secondary/.env" ]; then
    echo "SECONDARY .env file exists"
else
    echo "WARNING: secondary/.env file not found"
fi

# Check Docker services
echo -e "\nChecking Docker services..."
if docker ps | grep -q "kafka"; then
    echo "Kafka is running"
else
    echo "WARNING: Kafka is not running"
fi

if docker ps | grep -q "mysql"; then
    echo "MySQL is running"
else
    echo "WARNING: MySQL is not running"
fi

if docker ps | grep -q "kafka-connect"; then
    echo "Kafka Connect is running"
else
    echo "WARNING: Kafka Connect is not running"
fi

# Check Kafka Connect
echo -e "\nChecking Kafka Connect API..."
if curl -s -f http://localhost:8083/connectors > /dev/null; then
    echo "Kafka Connect API is accessible"
    
    # List connectors
    echo "Available connectors:"
    curl -s http://localhost:8083/connectors | jq -r '.[]'
else
    echo "WARNING: Kafka Connect API is not accessible"
fi

echo -e "\nSetup verification completed."