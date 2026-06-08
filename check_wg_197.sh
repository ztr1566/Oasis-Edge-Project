#!/bin/sh
# ==============================================================================
# WAN IP Checker — Avoid 197.x DPI-blocked ranges
# ==============================================================================
# Egyptian ISPs block WireGuard handshakes on 197.x.x.x IP ranges via DPI.
# This script reconnects PPPoE repeatedly (up to 5 attempts) until it gets
# a non-197 IP. Runs via cron every minute.
# ==============================================================================

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

COOLDOWN_FILE="/tmp/wan_reconnect_cooldown"
COOLDOWN=600        # 10 min cooldown after successful run or exhaustion
LOCK_FILE="/tmp/check_wg_197.lock"
MAX_RETRIES=5
DISCONNECT_WAIT=15  # seconds to keep interface down so RADIUS clears session
POLL_TIMEOUT=24     # seconds to wait for PPPoE negotiation

# 1. Prevent concurrent runs (Lock file check)
if [ -f "$LOCK_FILE" ]; then
    PID=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        # Quiet exit, another instance is already working
        exit 0
    fi
fi

# Set lock file
echo "$$" > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT INT TERM

# 2. Check Cooldown
if [ -f "$COOLDOWN_FILE" ]; then
    LAST=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    if [ $((NOW - LAST)) -lt $COOLDOWN ]; then
        exit 0
    fi
fi

# Helper to get current WAN IP
get_wan_ip() {
    ip -4 addr show pppoe-WAN 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1
}

WAN_IP=$(get_wan_ip)

# If WAN is down completely, don't do anything (netifd will bring it up)
if [ -z "$WAN_IP" ]; then
    exit 0
fi

# If WAN IP is not 197.x, we are good. Exit.
if ! echo "$WAN_IP" | grep -q "^197\."; then
    exit 0
fi

logger -t check_ip_wg "WAN IP is $WAN_IP (197.x detected). Starting reconnect loop..."

ATTEMPT=0
SUCCESS=0

while [ $ATTEMPT -lt $MAX_RETRIES ]; do
    ATTEMPT=$((ATTEMPT + 1))
    logger -t check_ip_wg "Attempt $ATTEMPT/$MAX_RETRIES: Bringing down WAN interface..."
    
    ifdown WAN
    sleep $DISCONNECT_WAIT
    
    logger -t check_ip_wg "Attempt $ATTEMPT/$MAX_RETRIES: Bringing up WAN interface..."
    ifup WAN
    
    # Poll for IP assignment
    POLL=0
    NEW_IP=""
    while [ $POLL -lt $POLL_TIMEOUT ]; do
        sleep 2
        NEW_IP=$(get_wan_ip)
        if [ -n "$NEW_IP" ]; then
            break
        fi
        POLL=$((POLL + 2))
    done
    
    if [ -z "$NEW_IP" ]; then
        logger -t check_ip_wg "Attempt $ATTEMPT/$MAX_RETRIES: WAN did not get an IP in ${POLL_TIMEOUT}s."
        continue
    fi
    
    if echo "$NEW_IP" | grep -q "^197\."; then
        logger -t check_ip_wg "Attempt $ATTEMPT/$MAX_RETRIES: Still got 197.x IP ($NEW_IP). Retrying..."
    else
        logger -t check_ip_wg "Attempt $ATTEMPT/$MAX_RETRIES: Successfully got clean IP $NEW_IP!"
        SUCCESS=1
        break
    fi
done

# Write cooldown timestamp
date +%s > "$COOLDOWN_FILE"

if [ $SUCCESS -eq 1 ]; then
    logger -t check_ip_wg "Reconnection sequence completed successfully."
else
    logger -t check_ip_wg "All $MAX_RETRIES reconnection attempts failed. Still on 197.x range. Cooling down."
fi
