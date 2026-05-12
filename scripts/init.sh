#!/usr/bin/env bash
set -euo pipefail

# --- Verify setup ---
echo "🔎 Verifying setup..."
"$(dirname "${BASH_SOURCE[0]}")/verify_setup.sh"



# --- usage & args ---
if [ $# -ne 1 ]; then
  echo "Usage: $0 <role>"
  echo "role: primary or secondary"
  exit 1
fi
ROLE=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
if [ "$ROLE" != "primary" ] && [ "$ROLE" != "secondary" ]; then
  echo "Error: Role must be 'primary' or 'secondary'"
  exit 1
fi

# --- paths ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$BASE_DIR/mysql-debezium/$ROLE"
ENV_EXAMPLE="$SOURCE_DIR/.env.example"
ENV_FILE="$SOURCE_DIR/.env"

[ -f "$ENV_EXAMPLE" ] || { echo "Error: $ENV_EXAMPLE not found"; exit 1; }

# --- ensure .env exists (or back it up if it does) ---
if [ ! -f "$ENV_FILE" ]; then
  echo "   Creating new $ENV_FILE from example..."
  cp "$ENV_EXAMPLE" "$ENV_FILE"
else
  echo "   $ENV_FILE exists. Backing up to $ENV_FILE.bak"
  cp -f "$ENV_FILE" "$ENV_FILE.bak"
  echo "   Creating new $ENV_FILE from example..."
  cp "$ENV_EXAMPLE" "$ENV_FILE"
fi

chmod 600 "$ENV_FILE"

echo "✅ $ENV_FILE created."
echo "----------------------------------------"
cat "$ENV_FILE"
echo "----------------------------------------"
echo "   Please fill in the required values in $ENV_FILE."

# --- Check for available ports ---
check_ports() {
    echo "🔎 Checking required ports availability..."
    local port_in_use=0
    # Define ports required for the 'primary' role
    local primary_ports=(3306 8083 9092 9093 8000)
    # Define ports required for the 'secondary' role
    local secondary_ports=(3306 8000)
    local ports_to_check=()

    if [ "$ROLE" = "primary" ]; then
        ports_to_check=("${primary_ports[@]}")
    else
        ports_to_check=("${secondary_ports[@]}")
    fi

    for port in "${ports_to_check[@]}"; do
        if nc -z 127.0.0.1 "$port" 2>/dev/null; then
            echo "   ❌ Error: Port $port is already in use."
            port_in_use=1
        else
            echo "   ✅ Port $port is available."
        fi
    done

    if [ $port_in_use -ne 0 ]; then
        echo "   Please stop the services using these ports and try again."
        exit 1
    fi
}
check_ports

# --- Start the application ---
echo "🚀 Starting the application..."
cd "$SOURCE_DIR"
if command -v docker-compose >/dev/null 2>&1; then
  docker-compose up -d
elif docker compose version >/dev/null 2>&1; then
  docker compose up -d
else
  echo "Error: Neither 'docker-compose' nor 'docker compose' was found."
  exit 1
fi

echo "✅ Application started successfully."
echo "ℹ️  Run 'docker-compose logs -f' in the '$SOURCE_DIR' directory to see the logs."
