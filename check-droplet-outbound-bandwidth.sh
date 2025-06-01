#!/bin/bash

# === CONFIGURATION ===
: "${HOME:=/home/<YOUR_USER_NAME>}" # TODO (1): Provide your user name

DROPLET_ID="$DROPLET_ID" # TODO (2): Provide your Droplet ID
INTERFACE="public"
DIRECTION="outbound"
THRESHOLD_GIB=950 # TODO (3): Update to accurate threshold for your Droplet
LOG_FILE="$HOME/logs/do_bandwidth.log"

# === LOAD SECRETS SECURELY ===
set -a
source "$HOME/.config/cron-secrets/env" # TODO (4): Create ~/.config/cron-secrets/env, add your DO API token
set +a

# === Validate API Token ===
if [[ -z "$DO_API_TOKEN" ]]; then
  echo "[✗] Missing DO_API_TOKEN environment variable."
  exit 1
fi

# === Check dependencies ===
for cmd in curl jq awk date bc; do
  if ! command -v $cmd &> /dev/null; then
    echo "[✗] Missing required command: $cmd"
    exit 1
  fi
done

# === Time Range: Last 30 Days ===
START=$(date -u -d "30 days ago" +%s)
END=$(date -u +%s)
START_ISO=$(date -u -d "@$START" +"%Y-%m-%dT%H:%M:%SZ")
END_ISO=$(date -u -d "@$END" +"%Y-%m-%dT%H:%M:%SZ")

# === Fetch Outbound Bandwidth ===
echo "[*] Querying DigitalOcean bandwidth metrics (Mbps) for the last 30 days..."
RESPONSE=$(curl -s -X GET \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DO_API_TOKEN" \
  "https://api.digitalocean.com/v2/monitoring/metrics/droplet/bandwidth?host_id=$DROPLET_ID&interface=$INTERFACE&direction=$DIRECTION&start=$START&end=$END")

# Find the correct result index first
RESULT_INDEX=$(echo "$RESPONSE" | jq -r --arg droplet_id "$DROPLET_ID" --arg interface "$INTERFACE" --arg direction "$DIRECTION" '
  .data.result | to_entries[] |
  select(.value.metric.host_id == $droplet_id and .value.metric.interface == $interface and .value.metric.direction == $direction) |
  .key')

echo "Found result index: $RESULT_INDEX"

# Calculate transfer using actual time differences between consecutive data points
TOTAL_BITS=$(echo "$RESPONSE" | jq -r '
  .data.result[0].values
  | map([.[0], (.[1] | tonumber)])
  | sort_by(.[0]) as $sorted
  | if ($sorted | length) < 2 then 0 else
      [range(1; $sorted | length) |
        (($sorted[.][0] - $sorted[.-1][0]) * $sorted[.-1][1] * 1000000)
      ] | add
    end')

if [[ -z "$TOTAL_BITS" || "$TOTAL_BITS" == "null" || "$TOTAL_BITS" == "0" ]]; then
  echo "[✗] Failed to retrieve or parse bandwidth data."
  echo "Response preview:"
  echo "$RESPONSE" | jq '.data.result[0]?.values[0:3]' 2>/dev/null || echo "$RESPONSE"
  exit 1
fi

# === Calculate derived metrics ===
TOTAL_BYTES=$(awk "BEGIN { printf \"%.0f\", $TOTAL_BITS / 8 }")
TOTAL_GIB=$(awk "BEGIN { printf \"%.2f\", $TOTAL_BYTES / (1024 * 1024 * 1024) }")
NOW_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SECONDS_TOTAL=$((END - START))
AVERAGE_KBPS=$(awk "BEGIN { printf \"%.2f\", $TOTAL_BITS / $SECONDS_TOTAL / 1000 }")

# === Get data point statistics ===
DATA_POINTS=$(echo "$RESPONSE" | jq '[.data.result[]?.values[]? | select(length == 2)] | length')
ACTUAL_START=$(echo "$RESPONSE" | jq -r '[.data.result[]?.values[]?[0]] | sort | .[0]')
ACTUAL_END=$(echo "$RESPONSE" | jq -r '[.data.result[]?.values[]?[0]] | sort | .[-1]')

# === Output ===
echo "[✓] $NOW_UTC - Estimated outbound bandwidth over last 30 days:"
echo "  Start:       $START_ISO"
echo "  End:         $END_ISO"
echo "  Data points: $DATA_POINTS"
echo "  Actual span: $(date -u -d "@$ACTUAL_START" +"%Y-%m-%d %H:%M") to $(date -u -d "@$ACTUAL_END" +"%Y-%m-%d %H:%M")"
echo "  Bytes:       $TOTAL_BYTES"
echo "  GiB:         $TOTAL_GIB"
echo "  Avg kbps:    $AVERAGE_KBPS"

echo "$NOW_UTC - Outbound (30d): $TOTAL_GIB GiB ($TOTAL_BYTES bytes, $DATA_POINTS points)" >> "$LOG_FILE"

# === Alert if over threshold ===
if (( $(echo "$TOTAL_GIB > $THRESHOLD_GIB" | bc -l) )); then
  echo "[!] WARNING: Outbound bandwidth exceeds ${THRESHOLD_GIB} GiB!"
  exit 2
fi
