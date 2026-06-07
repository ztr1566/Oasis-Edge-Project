#!/bin/sh
# Check WAN IP — reconnect with cooldown if on 197.x DPI block
COOLDOWN_FILE="/tmp/wan_reconnect_cooldown"
COOLDOWN=300  # 5 minute cooldown between reconnects

# Skip if recently reconnected
if [ -f "$COOLDOWN_FILE" ]; then
    LAST=$(cat "$COOLDOWN_FILE")
    NOW=$(date +%s)
    [ $((NOW - LAST)) -lt $COOLDOWN ] && exit 0
fi

WAN_IP=$(ip -4 addr show pppoe-WAN 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1)

if echo "$WAN_IP" | grep -q "^197\."; then
    logger -t check_ip_wg "WAN IP is $WAN_IP (197.x detected). Reconnecting WAN..."
    date +%s > "$COOLDOWN_FILE"
    ifdown WAN
    sleep 5
    ifup WAN
fi
