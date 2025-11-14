#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Function to show Docker installation instructions
show_docker_instructions() {
    local os=$1
    echo "Docker is not installed!"
    echo "Installation instructions for $os:"
    case $os in
        "ubuntu"|"debian")
            echo "Run these commands:"
            echo "  sudo apt-get update"
            echo "  sudo apt-get install -y docker.io"
            echo "  sudo apt-get install -y docker-compose-plugin"
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
    echo "Checking Docker Compose plugin..."
    
    # Check Docker Compose plugin (preferred method)
    if docker compose version &> /dev/null; then
        echo "Found Docker Compose plugin:"
        docker compose version
        return 0
    fi
    
    echo "Docker Compose plugin is not installed!"
    return 1
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

# Check Docker installation and permissions
echo "Checking Docker installation..."
if command -v docker &> /dev/null; then
    # Try to run docker version command
    if docker version &> /dev/null || sudo docker version &> /dev/null; then
        echo "Docker is installed and accessible"
        docker version | grep "Version" || sudo docker version | grep "Version"
    else
        echo "WARNING: Docker is installed but may have permission issues"
        echo "Try running: sudo usermod -aG docker $USER"
        echo "Then log out and log back in"
    fi
else
    show_docker_instructions $OS
    exit 1
fi

# Check Docker Compose plugin
echo -e "\nChecking Docker Compose installation..."
if docker compose version &> /dev/null; then
    echo "Found Docker Compose plugin:"
    docker compose version
else
    # Try with sudo
    if sudo docker compose version &> /dev/null; then
        echo "Docker Compose plugin is available with sudo"
        sudo docker compose version
    else
        echo "Docker Compose plugin is required but not found"
        show_docker_instructions $OS
        exit 1
    fi
fi

# Check environment files
echo -e "\nChecking environment files..."
if [ -f "../mysql-debezium-poc/primary/.env" ]; then
    echo "PRIMARY .env file exists"
    # Check for required variables
    if grep -q "PRIMARY_PUB_IP" "../mysql-debezium-poc/primary/.env"; then
        echo "PRIMARY_PUB_IP is configured"
    else
        echo "WARNING: PRIMARY_PUB_IP not found in primary/.env"
    fi
else
    echo "WARNING: primary/.env file not found"
fi

if [ -f "../mysql-debezium-poc/secondary/.env" ]; then
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