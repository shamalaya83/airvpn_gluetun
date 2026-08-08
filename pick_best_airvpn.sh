#!/bin/sh

# ------------------------------------------------------------------------------
# Script: pick_best_airvpn.sh
#
# Description:
# This script selects the best AirVPN server located in a specific country
# (default: Netherlands) by evaluating server load and avoiding exit nodes
# from the Tor network.
#
# Optionally, it also checks each IP with IPQualityScore and/or DroneBL.
#
# If FORCED_SERVER is set, skips all logic and directly sets SERVER_NAMES.
# ------------------------------------------------------------------------------

# === CONFIGURATION ===

GLUETUN_SERVERS_JSON="/gluetun/servers/airvpn.json"
COUNTRY="Netherlands"
MAX_ATTEMPTS=10

# Enable/disable additional checks

USE_IPQS_CHECK="${USE_IPQS_CHECK:-true}"
DRONEBL_CHECK="${DRONEBL_CHECK:-true}"
TOR_CHECK="${TOR_CHECK:-true}"

# Minimum bandwidth required
# 0 = no minimum bandwidth

MIN_BANDWIDTH="${MIN_BANDWIDTH:-0}"

# Forced server

#FORCED_SERVER="Alchiba"
FORCED_SERVER="${FORCED_SERVER:-}"

# === TOKEN ===

AIRVPN_API_KEY="XXX"
IPQS_API_KEY="XXX"

# === URL CONFIG ===

AIRVPN_API_URL="https://airvpn.org/api/status/?key=$AIRVPN_API_KEY"
TOR_EXIT_LIST_URL="https://check.torproject.org/exit-addresses"
IPQS_API_URL_BASE="https://ipqualityscore.com/api/json/ip"

# === Function to check if IP is listed in DroneBL ===

is_ip_listed_in_dronebl() {

    ip="$1"

    rev=$(echo "$ip" | awk -F. '{print $4"."$3"."$2"."$1}')

    DNSBLS="
    dnsbl.dronebl.org
    rbl.efnetrbl.org
    dnsbl.swiftbl.net
    combined.abuse.ch
    "

    for bl in $DNSBLS; do

        if dig +short "$rev.$bl" @1.1.1.1 | grep -qE '^[0-9]'; then
            echo "BLACKLISTED by $bl"
            return 0
        fi

        if dig +short "$rev.$bl" @8.8.8.8 | grep -qE '^[0-9]'; then
            echo "BLACKLISTED by $bl"
            return 0
        fi

    done

    return 1
}

echo "🌍 Selecting the best AirVPN server in $COUNTRY..."

echo "⚙️ Configuration:"
echo "   IPQualityScore check : $USE_IPQS_CHECK"
echo "   DroneBL check        : $DRONEBL_CHECK"
echo "   Tor check            : $TOR_CHECK"
echo "   Minimum bandwidth    : $MIN_BANDWIDTH"
echo "   Maximum attempts     : $MAX_ATTEMPTS"

# === Check if server is in gluetun server configuration ===

is_server_available_in_gluetun() {

    local server="$1"

    jq -e --arg server "$server" \
        '.servers[] | select(.server_name == $server)' \
        "$GLUETUN_SERVERS_JSON" >/dev/null
}

# === Forced mode ===

if [ -n "$FORCED_SERVER" ]; then

    echo "🚀 FORCED_SERVER provided, skipping checks."

    export SERVER_NAMES="$FORCED_SERVER"

    echo "🌐 Exported SERVER_NAMES=$SERVER_NAMES"

    exec /gluetun-entrypoint

    exit 0
fi

# === Install dependencies if missing ===

for cmd in curl jq; do

    if ! command -v "$cmd" >/dev/null 2>&1; then

        echo "📦 Installing $cmd..."

        apk add --no-cache "$cmd"

    fi

done

if ! command -v dig >/dev/null 2>&1; then

    echo "📦 Installing dig (bind-tools)..."

    apk add --no-cache bind-tools

fi

# === Check gluetun airvpn servers configuration ===

if [ ! -f "$GLUETUN_SERVERS_JSON" ]; then

    echo "❌ Gluetun server list not found: $GLUETUN_SERVERS_JSON"

    exit 1
fi

# === Validate MIN_BANDWIDTH ===

case "$MIN_BANDWIDTH" in
    ''|*[!0-9]*)
        echo "❌ MIN_BANDWIDTH must be a numeric value."
        exit 1
        ;;
esac

# === Fetch data ===

echo "📡 Downloading Tor exit node list..."

TOR_NODES=$(curl -s "$TOR_EXIT_LIST_URL")

if [ "$TOR_CHECK" = true ]; then

    TOR_NODES=$(echo "$TOR_NODES" | grep '^ExitAddress' | awk '{print $2}')

    echo "🧅 Tor check enabled."

else

    echo "🧅 Tor check disabled."

fi

echo "📡 Downloading AirVPN server data..."

SERVER_DATA=$(curl -s "$AIRVPN_API_URL")

if [ -z "$SERVER_DATA" ]; then

    echo "❌ Unable to retrieve AirVPN server data."

    exit 1
fi

# === Get server_best from countries[] ===

BEST_NAME=$(echo "$SERVER_DATA" | jq -r \
    --arg country "$COUNTRY" \
    '.countries[] | select(.country_name == $country) | .server_best')

echo "✨ AirVPN recommends: $BEST_NAME"

# === Filter all servers by country and health ===

CANDIDATES=$(echo "$SERVER_DATA" | jq -c \
    --arg country "$COUNTRY" \
    --argjson min_bw "$MIN_BANDWIDTH" '
    .servers[]
    | select(
        .country_name == $country
        and .health == "ok"
        and .bw_max > 0
        and .bw >= $min_bw
        and .ip_v4_in1 != null
    )
    | . + {
        load_score: ((.bw / .bw_max) + (.currentload / 100))
    }
    ' | jq -s \
    --arg best "$BEST_NAME" '
    [ .[] | select(.public_name == $best) ] +
    [ .[] | select(.public_name != $best) ]
    ')

CANDIDATE_COUNT=$(echo "$CANDIDATES" | jq 'length')

echo "🔎 Found $CANDIDATE_COUNT candidate server(s)."

if [ "$CANDIDATE_COUNT" -eq 0 ]; then

    echo "❌ No servers match the configured criteria."

    exit 1
fi

# === Check servers ===

ATTEMPT=0

for row in $(echo "$CANDIDATES" | jq -c '.[]'); do

    # Respect MAX_ATTEMPTS

    if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then

        echo "⚠️ Maximum number of attempts reached: $MAX_ATTEMPTS"

        break

    fi

    NAME=$(echo "$row" | jq -r '.public_name')
    IP=$(echo "$row" | jq -r '.ip_v4_in1')
    BW=$(echo "$row" | jq -r '.bw')
    BW_MAX=$(echo "$row" | jq -r '.bw_max')
    CURRENT_LOAD=$(echo "$row" | jq -r '.currentload')

    [ "$IP" = "null" ] && continue

    echo ""
    echo "============================================================"
    echo "🔎 Checking server: $NAME"
    echo "   AirVPN IP       : $IP"
    echo "   Bandwidth       : $BW / $BW_MAX"
    echo "   Current load    : $CURRENT_LOAD%"
    echo "============================================================"

    # === Check Gluetun server list ===

    echo "🔎 Checking if $NAME exists in Gluetun server list..."

    if ! is_server_available_in_gluetun "$NAME"; then

        echo "⛔ $NAME not found in $GLUETUN_SERVERS_JSON. Skipping."

        continue

    fi

    # Count actual attempts

    ATTEMPT=$((ATTEMPT + 1))

    # === Lookup external IP via DNS ===

    EXIT_IP=$(dig +short "${NAME}_exit.airservers.org" | head -n 1)

    if [ -z "$EXIT_IP" ]; then

        echo "❌ Could not resolve external IP for $NAME. Skipping."

        continue

    fi

    echo "🌐 Exit IP for $NAME is $EXIT_IP"

    # === Check DroneBL ===

    if [ "$DRONEBL_CHECK" = true ]; then

        echo "🔎 DroneBL check for $EXIT_IP..."

        if is_ip_listed_in_dronebl "$EXIT_IP"; then

            echo "⛔ $EXIT_IP is listed in DroneBL. Skipping."

            continue

        fi

        echo "✅ DroneBL check passed."

    else

        echo "⏭️ DroneBL check disabled."

    fi

    # === Check Tor exit ===

    if [ "$TOR_CHECK" = true ]; then

        echo "🔎 Tor check for $EXIT_IP..."

        if echo "$TOR_NODES" | grep -q -F "$EXIT_IP"; then

            echo "⛔ $EXIT_IP is a Tor exit node. Skipping."

            continue

        fi

        echo "✅ Tor check passed."

    else

        echo "⏭️ Tor check disabled."

    fi

    # === IPQualityScore check ===

    if [ "$USE_IPQS_CHECK" = true ]; then

        echo "🔎 IPQualityScore check for $EXIT_IP..."

        IPQS_RESULT=$(curl -s \
            "$IPQS_API_URL_BASE/$IPQS_API_KEY/$EXIT_IP")

        IS_TOR=$(echo "$IPQS_RESULT" | jq -r '.tor')

        if [ "$IS_TOR" = "true" ]; then

            echo "⛔ $EXIT_IP is flagged by IPQualityScore as Tor. Skipping."

            continue

        fi

        echo "✅ IPQualityScore check passed."

    else

        echo "⏭️ IPQualityScore check disabled."

    fi

    # === Server selected ===

    echo ""
    echo "============================================================"
    echo "✅ SELECTED SERVER"
    echo "   Server  : $NAME"
    echo "   AirVPN  : $IP"
    echo "   Exit IP : $EXIT_IP"
    echo "   BW      : $BW / $BW_MAX"
    echo "============================================================"

    export SERVER_NAMES="$NAME"

    echo "🌐 Exported SERVER_NAMES=$SERVER_NAMES"

    exec /gluetun-entrypoint

    exit 0

done

echo ""
echo "❌ No valid server found after $ATTEMPT attempts."

exit 1