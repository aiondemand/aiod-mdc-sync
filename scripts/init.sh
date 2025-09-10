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

# Detect public IP using multiple methods
get_public_ip() {
    local ip
    ip=$(curl -s ifconfig.me) || \
    ip=$(curl -s icanhazip.com) || \
    ip=$(curl -s ipecho.net/plain)
    
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    return 1
}

# Get IP
PUBLIC_IP=$(get_public_ip)
if [ $? -ne 0 ]; then
    echo "Error: Could not determine public IP"
    exit 1
fi

# Define paths
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$BASE_DIR/mysql-debezium-poc/$ROLE"
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
    sed -i "s/YOUR_PRIMARY_PUBLIC_IP/$PUBLIC_IP/" "$ENV_FILE"
else
    sed -i "s/YOUR_SECONDARY_PUBLIC_IP/$PUBLIC_IP/" "$ENV_FILE"
fi

# Set appropriate permissions
chmod 600 "$ENV_FILE"

echo "✅ Generated $ENV_FILE with IP: $PUBLIC_IP"
echo "📝 Please verify the contents of the file:"
echo "----------------------------------------"
cat "$ENV_FILE"
echo "----------------------------------------"
echo "ℹ️  Make sure to review the generated values before starting services"