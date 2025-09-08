#!/bin/bash

echo "Checking required ports availability..."

# Array of ports to check
PORTS=(3306 8000 8083 9092 9093)

for port in "${PORTS[@]}"; do
    if netstat -tuln | grep -q ":$port "; then
        echo "Port $port is in use"
        lsof -i :$port
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