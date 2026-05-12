#!/bin/bash

# Check if role argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <role>"
    echo "role: primary or secondary"
    exit 1
fi

ROLE=$(echo "$1" | tr '[:upper:]' '[:lower:]')

# Validate role
if [ "$ROLE" != "primary" ] && [ "$ROLE" != "secondary" ]; then
    echo "Error: Role must be 'primary' or 'secondary'"
    exit 1
fi

# Get local IP
get_local_ip() {
    # Try to get the primary network interface IP (eth0 or ens*)
    local ip=$(ip -4 addr show | grep -v 'docker' | grep -v 'br-' | grep -v 'lo' | grep 'inet' | grep -E 'eth0|ens' | head -1 | awk '{print $2}' | cut -d/ -f1)
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    # Fallback: try to get any non-docker, non-loopback IP
    ip=$(ip -4 addr show | grep -v 'docker' | grep -v 'br-' | grep -v 'lo' | grep 'inet' | head -1 | awk '{print $2}' | cut -d/ -f1)
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    return 1
}

# Get IP
LOCAL_IP=$(get_local_ip)
if [ $? -ne 0 ]; then
    echo "Error: Could not determine local IP"
    exit 1
fi

# Define paths
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$BASE_DIR/mysql-debezium/$ROLE"
ENV_EXAMPLE="$SOURCE_DIR/.env.example"
ENV_FILE="$SOURCE_DIR/.env"

# Check if .env.example exists
if [ ! -f "$ENV_EXAMPLE" ]; then
    echo "Error: $ENV_EXAMPLE not found"
    exit 1
fi

# Create .env file from example
cp "$ENV_EXAMPLE" "$ENV_FILE"

# Replace the IP placeholder based on role
if [ "$ROLE" == "primary" ]; then
    sed -i "s/YOUR_PRIMARY_PUBLIC_IP/$LOCAL_IP/" "$ENV_FILE"
else
    sed -i "s/YOUR_PRIMARY_PUBLIC_IP/$LOCAL_IP/" "$ENV_FILE"
fi

# Set appropriate permissions
chmod 600 "$ENV_FILE"

echo "✅ Generated $ENV_FILE with IP: $LOCAL_IP"
echo "📝 Please verify the contents of the file:"
echo "----------------------------------------"
cat "$ENV_FILE"
echo "----------------------------------------"
echo "ℹ️  Make sure the IP address is accessible from the other machine"
echo "   Test connectivity with: ping $LOCAL_IP"
