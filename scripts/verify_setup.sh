#!/bin/bash

# Function to show Docker installation instructions
show_docker_instructions() {
    local os=$1
    echo "Docker is not installed!"
    echo "Installation instructions for $os:"
    case $os in
        "ubuntu"|"debian")
            echo "Run these commands:"
            echo "  sudo apt-get update"
            echo "  sudo apt-get install -y docker.io docker-compose"
            ;;
        "centos"|"rhel"|"fedora")
            echo "Run these commands:"
            echo "  sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo"
            echo "  sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"
            ;;
        *)
            echo "Please visit https://docs.docker.com/engine/install/ for Docker installation"
            ;;
    esac
}

# Function to check Docker Compose version
check_docker_compose() {
    echo "Checking Docker Compose versions..."
    
    # Check standalone docker-compose
    if command -v docker-compose &> /dev/null; then
        echo "Found standalone Docker Compose:"
        docker-compose --version
    fi
    
    # Check Docker Compose plugin
    if docker compose version &> /dev/null; then
        echo "Found Docker Compose plugin:"
        docker compose version
    fi
    
    # If neither is found
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo "Docker Compose is not installed!"
        return 1
    fi
    return 0
}

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS=$(uname -s)
fi

echo "Verifying Debezium PoC Setup..."
echo "==============================="

# Check Docker and Docker Compose
echo "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    show_docker_instructions $OS
    exit 1
fi

# Check Docker Compose versions
check_docker_compose || {
    echo "Docker Compose is required but not found"
    show_docker_instructions $OS
    exit 1
}

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