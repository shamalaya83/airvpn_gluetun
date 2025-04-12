#!/bin/sh

# ------------------------------------------------------------------------------
# Script: pick_best_airvpn.sh
#
# Description:
#   This script selects the best AirVPN server located in a specific country 
#   (default: Netherlands) by evaluating server load and avoiding exit nodes 
#   from the Tor network. Optionally, it also checks each IP with 
#   IPQualityScore to further ensure it's not flagged as Tor or malicious.
#
#   Once a valid server is selected, it sets the SERVER_NAMES environment 
#   variable with the corresponding AirVPN hostname (e.g., "Zubeneschamali").
#
# Features:
#   - Sorts servers by load score (bandwidth usage + current load)
#   - Skips servers flagged as Tor exit nodes
#   - (Optional) Skips servers flagged by IPQualityScore
#   - Exports the selected server's hostname to SERVER_NAMES
#
# Configuration:
#   - COUNTRY: Target country for server selection
#   - AIRVPN_API_KEY: Your AirVPN API token
#   - IPQS_API_KEY: Your IPQualityScore API token
#   - USE_IPQS_CHECK: Set to "true" to enable IPQualityScore validation
#
# Usage:
#   This script is meant to be run as an entrypoint before launching Gluetun.
#
# ------------------------------------------------------------------------------

# === CONFIGURATION ===
COUNTRY="Netherlands"
MAX_ATTEMPTS=5
USE_IPQS_CHECK=true  # optional IPQualityScore check

# === TOKEN ===
AIRVPN_API_KEY="YOUR_API_KEY_AIRVPN"
IPQS_API_KEY="YOUR_API_KEY_IPQUALITYSCORE"

# === URL CONFIG ===
AIRVPN_API_URL="https://airvpn.org/api/status/?key=$AIRVPN_API_KEY"
TOR_EXIT_LIST_URL="https://check.torproject.org/exit-addresses"
IPQS_API_URL_BASE="https://ipqualityscore.com/api/json/ip"

echo "🌍 Selecting the best AirVPN server in $COUNTRY..."

# Install curl and jq if not present
if ! command -v curl >/dev/null 2>&1; then
  echo "📦 Installing curl..."
  apk add --no-cache curl
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "📦 Installing jq..."
  apk add --no-cache jq
fi

# Fetch Tor exit node list
TOR_NODES=$(curl -s "$TOR_EXIT_LIST_URL" | grep '^ExitAddress' | awk '{print $2}')

# Fetch AirVPN server data
SERVER_DATA=$(curl -s "$AIRVPN_API_URL")

# Filter and sort by load
CANDIDATES=$(echo "$SERVER_DATA" | jq -c --arg country "$COUNTRY" '
  .servers[]
  | select(.country_name == $country and .health == "ok" and .bw_max > 0)
  | . + {
      load_score: ((.bw / .bw_max) + (.currentload / 100))
    }
' | jq -s 'sort_by(.load_score)')

ATTEMPT=0
for row in $(echo "$CANDIDATES" | jq -c '.[]'); do
  NAME=$(echo "$row" | jq -r '.public_name')
  IP=$(echo "$row" | jq -r '.ip_v4_in1')
  [ "$IP" = "null" ] && continue
  ATTEMPT=$((ATTEMPT + 1))

  echo "🔍 Checking server $NAME → $IP"

  # Skip if Tor exit node
  if echo "$TOR_NODES" | grep -q "$IP"; then
    echo "⚠️ $IP is a Tor exit node. Skipping."
    continue
  fi

  # Optional: Check with IPQualityScore
  if [ "$USE_IPQS_CHECK" = true ]; then
    echo "🔎 IPQualityScore check enabled for $IP..."
    IPQS_RESULT=$(curl -s "$IPQS_API_URL_BASE/$IPQS_API_KEY/$IP")
    IS_TOR=$(echo "$IPQS_RESULT" | jq -r '.tor')

    if [ "$IS_TOR" = "true" ]; then
      echo "⚠️ $IP is marked as Tor by IPQS. Skipping."
      continue
    fi
  fi

  echo "✅ Selected $NAME → $IP"
  export SERVER_NAMES="${NAME}"
  echo "🌐 Exported SERVER_NAMES=$SERVER_NAMES"
  exec /gluetun-entrypoint
done

echo "❌ No valid server found after $MAX_ATTEMPTS attempts."
exit 1
