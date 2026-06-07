#!/bin/sh
# ==============================================================================
# AdGuardHome IPv6 Client Sync — REST API (v2 — debounced)
# ==============================================================================
# Updates AGH persistent clients with current IPv6 addresses.
# Only updates clients whose addresses actually changed (per-client diff).
# Includes a 5-minute cooldown after each update cycle to avoid hammering AGH.
# Runs via cron every 2 minutes: */2 * * * * /root/sync_agh_ipv6_clients.sh
# ==============================================================================

LOCKFILE="/tmp/agh_sync.lock"
STATEDIR="/tmp/agh_ipv6_state.d"
COOLDOWN_FILE="/tmp/agh_sync_cooldown"
COOLDOWN=300  # 5 minutes between update cycles
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

# Cooldown check — skip if we updated recently
if [ -f "$COOLDOWN_FILE" ]; then
    LAST=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    [ $((NOW - LAST)) -lt $COOLDOWN ] && exit 0
fi

mkdir -p "$STATEDIR"

# Get current IPv6 neighbor cache (global addresses only, all states)
NEIGH_CACHE=$(ip -6 neigh show dev br-lan 2>/dev/null | grep lladdr | grep -v "^fe80")

# Helper: get all global IPv6 for a MAC
get_v6() {
    echo "$NEIGH_CACHE" | grep -i "$1" | awk '{print $1}' | sort
}

# Update a single client via API — only if its IPv6 set changed
# Args: NAME IPV4 MAC
# Returns: 0 if updated, 1 if skipped
update_client() {
    NAME="$1"
    IPV4="$2"
    MAC="$3"
    CLIENT_STATE="$STATEDIR/$NAME"

    # Get all current IPv6 addresses for this MAC
    V6_LIST=$(get_v6 "$MAC")

    # Build per-client state fingerprint
    CURRENT_STATE="$IPV4:$(echo "$V6_LIST" | tr '\n' ',')"

    # Compare with last known state — skip if unchanged
    if [ -f "$CLIENT_STATE" ] && [ "$(cat "$CLIENT_STATE")" = "$CURRENT_STATE" ]; then
        return 1
    fi

    # Build JSON ids array: always starts with IPv4
    IDS="\"$IPV4\""
    for V6 in $V6_LIST; do
        [ -n "$V6" ] && IDS="$IDS,\"$V6\""
    done

    # Write JSON to temp file
    cat > /tmp/agh_update.json << EOF
{"name":"$NAME","data":{"name":"$NAME","ids":[$IDS],"tags":[],"blocked_services":[],"upstreams":[],"use_global_settings":true,"use_global_blocked_services":true,"filtering_enabled":false,"parental_enabled":false,"safebrowsing_enabled":false,"safe_search":{"enabled":false,"bing":false,"duckduckgo":false,"ecosia":false,"google":false,"pixabay":false,"yandex":false,"youtube":false},"ignore_querylog":false,"ignore_statistics":false}}
EOF

    RESP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "$AUTH" \
        -H "Content-Type: application/json" \
        -d @/tmp/agh_update.json \
        "$AGH/clients/update" 2>/dev/null)

    V6_COUNT=$(echo "$V6_LIST" | grep -c . 2>/dev/null || echo 0)
    if [ "$RESP" = "200" ]; then
        echo "$CURRENT_STATE" > "$CLIENT_STATE"
        logger -t agh-sync "Updated $NAME: IPv4=$IPV4, IPv6=$V6_COUNT addrs"
    else
        logger -t agh-sync "FAILED $NAME: HTTP $RESP"
    fi
    return 0
}

UPDATED=0

# Only update clients that actually changed
update_client "Samsung-TV"      "192.168.2.100" "80:47:86:68:e3:3d" && UPDATED=$((UPDATED+1))
update_client "Ghada-S9"        "192.168.2.101" "24:18:1d:81:a7:f2" && UPDATED=$((UPDATED+1))
update_client "Redmi-Note8-Pro" "192.168.2.102" "92:4d:25:58:51:b2" && UPDATED=$((UPDATED+1))
update_client "Honor-Pad-X7"    "192.168.2.103" "cc:62:00:38:98:ef" && UPDATED=$((UPDATED+1))
update_client "Predator"        "192.168.2.104" "34:e1:2d:4b:3a:07" && UPDATED=$((UPDATED+1))
update_client "Sara-Note10"     "192.168.2.105" "04:e5:98:62:04:13" && UPDATED=$((UPDATED+1))
update_client "Lenovo"          "192.168.2.106" "b0:fc:36:29:5a:ff" && UPDATED=$((UPDATED+1))
update_client "Ziad-A55"        "192.168.2.107" "78:b6:fe:40:59:2f" && UPDATED=$((UPDATED+1))
update_client "Amira-IPhone"    "192.168.2.108" "90:a2:5b:0c:b3:bd" && UPDATED=$((UPDATED+1))

rm -f /tmp/agh_update.json

if [ "$UPDATED" -gt 0 ]; then
    date +%s > "$COOLDOWN_FILE"
    logger -t agh-sync "AGH sync done: $UPDATED client(s) updated, cooldown 5m"
fi
