#!/usr/bin/env bash
set -euo pipefail

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

# --- robust public IP detection ---
get_public_ip() {
  local ip endpoint
  for endpoint in \
    "https://api.ipify.org" \
    "https://ifconfig.me/ip" \
    "https://icanhazip.com"
  do
    ip=$(curl -fsSL --max-time 5 "$endpoint" 2>/dev/null | tr -d '\r\n')
    if [ -n "${ip:-}" ]; then
      printf '%s\n' "$ip"
      return 0
    fi
  done
  if command -v dig >/dev/null 2>&1; then
    ip=$(dig +time=3 +tries=1 +short myip.opendns.com @resolver1.opendns.com | tr -d '\r\n')
    if [ -n "${ip:-}" ]; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi
  return 1
}
PUBLIC_IP="$(get_public_ip)" || { echo "Error: Could not determine public IP"; exit 1; }

# --- paths ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$BASE_DIR/mysql-debezium-poc/$ROLE"
ENV_EXAMPLE="$SOURCE_DIR/.env.example"
ENV_FILE="$SOURCE_DIR/.env"

[ -f "$ENV_EXAMPLE" ] || { echo "Error: $ENV_EXAMPLE not found"; exit 1; }

# --- sed -i portability (BSD vs GNU) ---
if sed --version >/dev/null 2>&1; then
  SED_INPLACE=(-i)
else
  SED_INPLACE=(-i '')
fi

# --- ensure .env exists (or back it up if it does) ---
if [ ! -f "$ENV_FILE" ]; then
  echo "   Creating new $ENV_FILE from example..."
  cp "$ENV_EXAMPLE" "$ENV_FILE"
else
  echo "   $ENV_FILE exists. Backing up to $ENV_FILE.bak"
  cp -f "$ENV_FILE" "$ENV_FILE.bak"
fi

# Choose a delimiter that won't appear in the pattern/replacement
DELIM='~'
# Escape replacement for sed: escape delimiter and '&'
REPL=${PUBLIC_IP//${DELIM}/\\${DELIM}}
REPL=${REPL//&/\\&}

# Helper: upsert KEY=VALUE (replace existing line starting with KEY=, or append)
upsert_kv () {
  local key="$1" val="$2" escval
  escval=${val//${DELIM}/\\${DELIM}}
  escval=${escval//&/\\&}
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed "${SED_INPLACE[@]}" -E "s${DELIM}^${key}=.*${DELIM}${key}=${escval}${DELIM}" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE"
  fi
}

# 1) Replace any known placeholders anywhere in the file (use ~ as delimiter)
if [ "$ROLE" = "primary" ]; then
  sed "${SED_INPLACE[@]}" -E "s${DELIM}(YOUR_PRIMARY_PUBLIC_IP|PRIMARY_VM_IP_OR_DNS)${DELIM}${REPL}${DELIM}g" "$ENV_FILE" || true
else
  sed "${SED_INPLACE[@]}" -E "s${DELIM}(YOUR_SECONDARY_PUBLIC_IP|SECONDARY_VM_IP_OR_DNS)${DELIM}${REPL}${DELIM}g" "$ENV_FILE" || true
fi

# 2) Explicitly upsert the authoritative keys (both naming styles)
if [ "$ROLE" = "primary" ]; then
  upsert_kv "PRIMARY_PUB_IP" "$PUBLIC_IP"
  upsert_kv "PRIMARY_PUBLIC_IP" "$PUBLIC_IP"
else
  upsert_kv "SECONDARY_PUB_IP" "$PUBLIC_IP"
  upsert_kv "SECONDARY_PUBLIC_IP" "$PUBLIC_IP"
fi

chmod 600 "$ENV_FILE"

echo "✅ $ENV_FILE updated with IP: $PUBLIC_IP"
echo "----------------------------------------"
cat "$ENV_FILE"
echo "----------------------------------------"
echo "   If you still see a placeholder, show me that exact line and I’ll add it to the replacement list."

