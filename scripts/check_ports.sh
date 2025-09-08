#!/bin/bash

echo "Checking required ports availability..."

# Define ports and their configuration locations
declare -A PORT_CONFIG=(
    [3306]="MySQL port - Edit MYSQL_PORT in primary/.env and secondary/.env"
    [8000]="FastAPI port - Edit app service ports in primary/docker-compose.yml and secondary/docker-compose.yml"
    [8083]="Kafka Connect port - Edit kafka-connect service ports in primary/docker-compose.yml"
    [9092]="Kafka internal port - Edit KAFKA_ADVERTISED_LISTENERS in primary/docker-compose.yml"
    [9093]="Kafka external port - Edit KAFKA_ADVERTISED_LISTENERS in primary/docker-compose.yml"
)

# Function to show how to change port
show_port_fix() {
    local port=$1
    echo "To change port $port:"
    echo "- ${PORT_CONFIG[$port]}"
    case $port in
        3306)
            echo "Example:"
            echo "  MYSQL_PORT=3307  # in .env files"
            ;;
        8000)
            echo "Example:"
            echo "  ports:"
            echo "    - 8001:8000  # in docker-compose.yml"
            ;;
        8083)
            echo "Example:"
            echo "  ports:"
            echo "    - 8084:8083  # in docker-compose.yml"
            ;;
        9092|9093)
            echo "Example in primary/docker-compose.yml:"
            echo "  KAFKA_ADVERTISED_LISTENERS: >-"
            echo "    INTERNAL://kafka:9094,EXTERNAL://\${PRIMARY_PUB_IP}:9095"
            ;;
    esac
    echo
}

# Check each port
for port in "${!PORT_CONFIG[@]}"; do
    if netstat -tuln | grep -q ":$port "; then
        echo "Port $port is in use"
        lsof -i :$port
        show_port_fix $port
    else
        echo "Port $port is available"
    fi
done

# Check if ports are accessible from other VM
if [ ! -z "$1" ]; then
    echo -e "\nChecking connectivity to remote host $1..."
    for port in "${PORTS[@]}"; do
        nc -zv $1 $port 2>&1
    done
fi