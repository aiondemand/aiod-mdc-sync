#!/usr/bin/env bash
set -euo pipefail

PRIMARY_API="${PRIMARY_API_URL:-}"
SECONDARY_API="${SECONDARY_API_URL:-}"
TIMEOUT=120
INTERVAL=5
PAYLOAD_FILE=""

usage() {
  cat <<USAGE
Usage: ${0##*/} --primary <primary_api_url> --secondary <secondary_api_url> [--timeout <seconds>] [--interval <seconds>]

Creates a uniquely named item on the primary API and polls the secondary API until
it appears, confirming end-to-end replication across the internet. Environment
variables PRIMARY_API_URL and SECONDARY_API_URL can be used instead of flags.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --primary)
      PRIMARY_API="$2"; shift 2;;
    --secondary)
      SECONDARY_API="$2"; shift 2;;
    --timeout)
      TIMEOUT="$2"; shift 2;;
    --interval)
      INTERVAL="$2"; shift 2;;
    --payload)
      PAYLOAD_FILE="$2"; shift 2;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2
      usage; exit 1;;
  esac
done

if [[ -z "$PRIMARY_API" || -z "$SECONDARY_API" ]]; then
  echo "ERROR: Both --primary and --secondary URLs are required (or set PRIMARY_API_URL / SECONDARY_API_URL)." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required for JSON parsing." >&2
  exit 1
fi

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || ! [[ "$INTERVAL" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --timeout and --interval must be positive integers." >&2
  exit 1
fi

if [[ -n "$PAYLOAD_FILE" && ! -f "$PAYLOAD_FILE" ]]; then
  echo "ERROR: Payload file '$PAYLOAD_FILE' not found." >&2
  exit 1
fi

UUID="$(uuidgen 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())')"
NAME="internet-check-$UUID"
DESC="Replicated via Debezium over internet at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ -n "$PAYLOAD_FILE" ]]; then
  CREATE_BODY="$(cat "$PAYLOAD_FILE")"
else
  CREATE_BODY="$(python3 - <<PY
import json, sys
payload = {
    "name": "$NAME",
    "description": "$DESC"
}
json.dump(payload, sys.stdout)
PY
)"
fi

echo "Creating item on primary: $PRIMARY_API/items"
CREATE_RESPONSE="$(curl -fsS -X POST -H 'Content-Type: application/json' -d "$CREATE_BODY" "$PRIMARY_API/items")"

ITEM_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$CREATE_RESPONSE" 2>/dev/null || true)"
if [[ -z "$ITEM_ID" ]]; then
  echo "ERROR: Unable to determine created item id from primary response: $CREATE_RESPONSE" >&2
  exit 1
fi

echo "Created item id=$ITEM_ID, name=$NAME"

echo "Polling secondary: $SECONDARY_API/items"
START_TS=$(date +%s)
END_TS=$((START_TS + TIMEOUT))
FOUND=false

while [[ $(date +%s) -le $END_TS ]]; do
  RESPONSE="$(curl -fsS "$SECONDARY_API/items" 2>/dev/null || true)"
  if [[ -n "$RESPONSE" ]]; then
    if RESPONSE_JSON="$RESPONSE" python3 - "$ITEM_ID" "$NAME" <<'PY'; then
import json, os, sys
items = json.loads(os.environ["RESPONSE_JSON"])
item_id = sys.argv[1]
item_name = sys.argv[2]
for item in items:
    if str(item.get("id")) == item_id and item.get("name") == item_name:
        sys.exit(0)
sys.exit(1)
PY
    then
      FOUND=true
      break
    fi
  fi
  sleep "$INTERVAL"
done

if ! $FOUND; then
  echo "ERROR: Item id=$ITEM_ID not observed on secondary within ${TIMEOUT}s." >&2
  exit 2
fi

TOTAL=$(( $(date +%s) - START_TS ))
echo "Success! Item replicated to secondary in ${TOTAL}s."
exit 0
