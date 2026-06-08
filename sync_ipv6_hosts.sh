#!/bin/sh
# ==============================================================================
# IPv6 SLAAC Hostname Sync Script (Zero-Stall)
# ==============================================================================
# Maps ALL IPv6 neighbor cache entries to hostnames by cross-referencing
# MAC addresses with DHCPv4 lease names. Maps all global-scope (GUA)
# addresses per device (not just shortest) to ensure AdGuard Home can
# identify queries from any IPv6 address including privacy extensions.
# Runs via cron every 2 minutes.
# ==============================================================================

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

TMP_FILE="/tmp/hosts/ipv6_slaac.tmp"
FINAL_FILE="/tmp/hosts/ipv6_slaac"

# Ensure the directory exists
mkdir -p /tmp/hosts

> "$TMP_FILE"

# Parse ALL IPv6 neighbor entries (REACHABLE, STALE, DELAY, PROBE)
ip -6 neigh show dev br-lan | grep lladdr | while read -r IP _ MAC _; do
    [ -z "$MAC" ] && continue

    # Skip link-local addresses (fe80::) and multicast (ff00::)
    case "$IP" in
        fe80:*|ff*) continue ;;
    esac

    # Find hostname in IPv4 DHCP leases matching this MAC
    HOSTNAME=$(awk -v mac="$MAC" 'tolower($2) == tolower(mac) {print $4}' /tmp/dhcp.leases | head -n 1)

    if [ -n "$HOSTNAME" ] && [ "$HOSTNAME" != "*" ]; then
        echo "$IP $HOSTNAME.lan $HOSTNAME" >> "$TMP_FILE"
    fi
done

# Keep ALL addresses per hostname (not just shortest)
sort -u "$TMP_FILE" > "${TMP_FILE}.sorted"
mv "${TMP_FILE}.sorted" "$TMP_FILE"

# Only reload dnsmasq via SIGHUP if the file actually changed
if ! cmp -s "$TMP_FILE" "$FINAL_FILE"; then
    mv "$TMP_FILE" "$FINAL_FILE"
    killall -HUP dnsmasq >/dev/null 2>&1
else
    rm -f "$TMP_FILE"
fi
