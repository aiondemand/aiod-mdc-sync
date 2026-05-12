#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: ${0##*/} [--public-address <IP-or-DNS>] [--password <pass>] [--san <extraSAN>] [--force]

Creates a small certificate authority, Kafka broker certificate, and client truststore
for the Debezium project. By default the script reads PRIMARY_PUB_IP and KAFKA_SSL_PASSWORD
from primary/.env if present. Use --public-address to override the SAN advertised to
remote clients. Certificates are written to:
  mysql-debezium/primary/secrets/
  mysql-debezium/secondary/secrets/

Re-run with --force to overwrite existing material.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRIMARY_ENV="$REPO_ROOT/mysql-debezium/primary/.env"
PRIMARY_SECRETS="$REPO_ROOT/mysql-debezium/primary/secrets"
SECONDARY_SECRETS="$REPO_ROOT/mysql-debezium/secondary/secrets"

[[ -f "$PRIMARY_ENV" ]] && set -a && source "$PRIMARY_ENV" && set +a

PUBLIC_ADDR="${PRIMARY_PUB_IP:-kf-aiod-dev.iti.es}"
PASSWORD="${KAFKA_SSL_PASSWORD:-changeit}"
EXTRA_SAN=()
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-address)
      PUBLIC_ADDR="$2"; shift 2;;
    --password)
      PASSWORD="$2"; shift 2;;
    --san)
      EXTRA_SAN+=("$2"); shift 2;;
    --force)
      FORCE=true; shift 1;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2
      usage; exit 1;;
  esac
done

if [[ -z "$PUBLIC_ADDR" ]]; then
  echo "ERROR: Unable to determine primary public address. Set PRIMARY_PUB_IP in primary/.env or pass --public-address." >&2
  exit 1
fi

if [[ -z "$PASSWORD" ]]; then
  echo "ERROR: TLS password cannot be empty." >&2
  exit 1
fi

for tool in openssl docker; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: Required tool '$tool' not found in PATH." >&2
    exit 1
  fi
done

mkdir -p "$PRIMARY_SECRETS" "$SECONDARY_SECRETS"

if ! $FORCE; then
  for f in ca.crt kafka.server.keystore.p12 kafka.server.truststore.p12; do
    if [[ -f "$PRIMARY_SECRETS/$f" ]]; then
      echo "ERROR: $PRIMARY_SECRETS/$f already exists. Re-run with --force to overwrite." >&2
      exit 1
    fi
  done
  if [[ -f "$SECONDARY_SECRETS/kafka.client.truststore.p12" ]]; then
    echo "ERROR: $SECONDARY_SECRETS/kafka.client.truststore.p12 already exists. Re-run with --force to overwrite." >&2
    exit 1
  fi
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

cat >"$TMP_DIR/openssl.cnf" <<OPENSSL
[ req ]
default_bits        = 4096
distinguished_name  = req_distinguished_name
req_extensions      = v3_req
prompt              = no

[ req_distinguished_name ]
CN = Debezium-Primary-Kafka

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = kafka
DNS.2 = localhost
IP.1 = 127.0.0.1
OPENSSL

SAN_INDEX=2
if [[ "$PUBLIC_ADDR" =~ ^[0-9.]+$ ]]; then
  printf 'IP.%d = %s\n' "$((SAN_INDEX+1))" "$PUBLIC_ADDR" >>"$TMP_DIR/openssl.cnf"
else
  printf 'DNS.%d = %s\n' "$((SAN_INDEX+1))" "$PUBLIC_ADDR" >>"$TMP_DIR/openssl.cnf"
fi

for san in "${EXTRA_SAN[@]}"; do
  if [[ "$san" =~ ^[0-9.]+$ ]]; then
    SAN_INDEX=$((SAN_INDEX+1))
    printf 'IP.%d = %s\n' "$SAN_INDEX" "$san" >>"$TMP_DIR/openssl.cnf"
  else
    SAN_INDEX=$((SAN_INDEX+1))
    printf 'DNS.%d = %s\n' "$SAN_INDEX" "$san" >>"$TMP_DIR/openssl.cnf"
  fi
done

# 1) Create a simple certificate authority
openssl genrsa -out "$PRIMARY_SECRETS/ca.key" 4096 >/dev/null 2>&1
openssl req -x509 -new -key "$PRIMARY_SECRETS/ca.key" -sha256 -days 3650 \
  -out "$PRIMARY_SECRETS/ca.crt" -subj "/CN=Debezium-project-CA" >/dev/null 2>&1

# 2) Create broker key/certificate signed by the CA
openssl genrsa -out "$TMP_DIR/kafka.key" 4096 >/dev/null 2>&1
openssl req -new -key "$TMP_DIR/kafka.key" -out "$TMP_DIR/kafka.csr" -config "$TMP_DIR/openssl.cnf" >/dev/null 2>&1
openssl x509 -req -in "$TMP_DIR/kafka.csr" -CA "$PRIMARY_SECRETS/ca.crt" -CAkey "$PRIMARY_SECRETS/ca.key" \
  -CAcreateserial -out "$PRIMARY_SECRETS/kafka.server.crt" -days 825 -sha256 \
  -extensions v3_req -extfile "$TMP_DIR/openssl.cnf" >/dev/null 2>&1

openssl pkcs12 -export -in "$PRIMARY_SECRETS/kafka.server.crt" -inkey "$TMP_DIR/kafka.key" \
  -certfile "$PRIMARY_SECRETS/ca.crt" -name kafka-broker \
  -out "$PRIMARY_SECRETS/kafka.server.keystore.p12" -passout pass:"$PASSWORD" >/dev/null 2>&1

# 3) Build broker truststore (optional but useful for future mTLS)
docker run --rm \
  -e PASSWORD="$PASSWORD" \
  -v "$PRIMARY_SECRETS:/secrets" \
  eclipse-temurin:17-jdk \
  keytool -importcert -noprompt -alias CARoot -file /secrets/ca.crt \
    -keystore /secrets/kafka.server.truststore.p12 -storepass "$PASSWORD" -storetype PKCS12 >/dev/null 2>&1

# 4) Create client truststore for the secondary VM
docker run --rm \
  -e PASSWORD="$PASSWORD" \
  -v "$PRIMARY_SECRETS:/primary" \
  -v "$SECONDARY_SECRETS:/secondary" \
  eclipse-temurin:17-jdk \
  sh -c "set -eu; cp /primary/ca.crt /secondary/ca.crt; \
    keytool -importcert -noprompt -alias CARoot -file /primary/ca.crt \
      -keystore /secondary/kafka.client.truststore.p12 -storepass \"\$PASSWORD\" -storetype PKCS12" >/dev/null 2>&1

chmod 600 "$PRIMARY_SECRETS"/ca.key "$PRIMARY_SECRETS"/kafka.server.keystore.p12 \
  "$PRIMARY_SECRETS"/kafka.server.truststore.p12 "$SECONDARY_SECRETS"/kafka.client.truststore.p12

cat <<SUMMARY
TLS material created successfully.
  Broker keystore : $PRIMARY_SECRETS/kafka.server.keystore.p12
  Broker truststore: $PRIMARY_SECRETS/kafka.server.truststore.p12
  CA certificate  : $PRIMARY_SECRETS/ca.crt
  Client truststore: $SECONDARY_SECRETS/kafka.client.truststore.p12

Copy the contents of $SECONDARY_SECRETS to the secondary VM (for example via scp)
and configure secondary/.env with CONNECT_SSL_TRUSTSTORE_PASSWORD=$PASSWORD.
SUMMARY
