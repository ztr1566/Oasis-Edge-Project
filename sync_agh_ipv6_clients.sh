#!/bin/sh
# ==============================================================================
# AdGuardHome IPv6 Client Sync — REST API
# ==============================================================================
# Updates AGH persistent clients with ALL current IPv6 addresses.
# Uses the AGH REST API /clients/update endpoint.
# Runs via cron every 1 minute: * * * * * /root/sync_agh_ipv6_clients.sh
# ==============================================================================

LOCKFILE="/tmp/agh_sync.lock"
STATEFILE="/tmp/agh_ipv6_state"
AGH="http://192.168.2.1:8080/control"
AUTH="Authorization: Basic YOUR_AGH_AUTH_BASE64"

# Prevent concurrent runs (with stale lock cleanup)
if [ -f "$LOCKFILE" ]; then
    LOCK_AGE=$(( $(date +%s) - $(date -r "$LOCKFILE" +%s 2>/dev/null || echo 0) ))
    [ "$LOCK_AGE" -lt 120 ] && exit 0
    rm -f "$LOCKFILE"
fi
trap 'rm -f $LOCKFILE' EXIT
touch "$LOCKFILE"

# Get current IPv6 neighbor cache (global addresses only, all states)
NEIGH_CACHE=$(ip -6 neigh show dev br-lan 2>/dev/null | grep lladdr | grep -v "^fe80")

# Helper: get all global IPv6 for a MAC
get_v6() {
    echo "$NEIGH_CACHE" | grep -i "$1" | awk '{print $1}' | sort
}

# Build current state fingerprint
build_state() {
    echo "Samsung-TV:$(get_v6 '80:47:86:68:e3:3d' | tr '\n' ',')"
    echo "Ghada-S9:$(get_v6 '24:18:1d:81:a7:f2' | tr '\n' ',')"
    echo "Redmi-Note8-Pro:$(get_v6 '92:4d:25:58:51:b2' | tr '\n' ',')"
    echo "Honor-Pad-X7:$(get_v6 'cc:62:00:38:98:ef' | tr '\n' ',')"
    echo "Predator:$(get_v6 '34:e1:2d:4b:3a:07' | tr '\n' ',')"
    echo "Sara-Note10:$(get_v6 '04:e5:98:62:04:13' | tr '\n' ',')"
    echo "Lenovo:$(get_v6 'b0:fc:36:29:5a:ff' | tr '\n' ',')"
    echo "Ziad-A55:$(get_v6 '78:b6:fe:40:59:2f' | tr '\n' ',')"
    echo "Amira-IPhone:$(get_v6 '90:a2:5b:0c:b3:bd' | tr '\n' ',')"
}

build_state > "${STATEFILE}.new"

# Check if anything changed
if cmp -s "${STATEFILE}.new" "$STATEFILE" 2>/dev/null; then
    rm -f "${STATEFILE}.new"
    exit 0
fi

logger -t agh-sync "IPv6 addresses changed, updating AGH clients"

# Update a single client via API
# Args: NAME IPV4 MAC
update_client() {
    NAME="$1"
    IPV4="$2"
    MAC="$3"

    # Get all current IPv6 addresses for this MAC
    V6_LIST=$(get_v6 "$MAC")

    # Build JSON ids array: always starts with IPv4
    IDS="\"$IPV4\""
    for V6 in $V6_LIST; do
        [ -n "$V6" ] && IDS="$IDS,\"$V6\""
    done

    # Write JSON to temp file (blocked_services must be [] not object for AGH 0.107.x)
    cat > /tmp/agh_update.json << EOF
{"name":"$NAME","data":{"name":"$NAME","ids":[$IDS],"tags":[],"blocked_services":[],"upstreams":[],"use_global_settings":true,"use_global_blocked_services":true,"filtering_enabled":false,"parental_enabled":false,"safebrowsing_enabled":false,"safe_search":{"enabled":false,"bing":false,"duckduckgo":false,"ecosia":false,"google":false,"pixabay":false,"yandex":false,"youtube":false},"ignore_querylog":false,"ignore_statistics":false}}
EOF

    # POST update via curl (more reliable than wget for POST)
    RESP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "$AUTH" \
        -H "Content-Type: application/json" \
        -d @/tmp/agh_update.json \
        "$AGH/clients/update" 2>/dev/null)

    V6_COUNT=$(echo "$V6_LIST" | grep -c . 2>/dev/null || echo 0)
    if [ "$RESP" = "200" ]; then
        logger -t agh-sync "Updated $NAME: IPv4=$IPV4, IPv6=$V6_COUNT addrs"
    else
        logger -t agh-sync "FAILED $NAME: HTTP $RESP"
    fi
}

update_client "Samsung-TV"      "192.168.2.100" "80:47:86:68:e3:3d"
update_client "Ghada-S9"        "192.168.2.101" "24:18:1d:81:a7:f2"
update_client "Redmi-Note8-Pro" "192.168.2.102" "92:4d:25:58:51:b2"
update_client "Honor-Pad-X7"    "192.168.2.103" "cc:62:00:38:98:ef"
update_client "Predator"        "192.168.2.104" "34:e1:2d:4b:3a:07"
update_client "Sara-Note10"     "192.168.2.105" "04:e5:98:62:04:13"
update_client "Lenovo"          "192.168.2.106" "b0:fc:36:29:5a:ff"
update_client "Ziad-A55"        "192.168.2.107" "78:b6:fe:40:59:2f"
update_client "Amira-IPhone"    "192.168.2.108" "90:a2:5b:0c:b3:bd"

mv "${STATEFILE}.new" "$STATEFILE"
rm -f /tmp/agh_update.json
logger -t agh-sync "AGH client sync complete"
