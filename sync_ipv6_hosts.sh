#!/bin/sh
# ==============================================================================
# IPv6 SLAAC Hostname Sync Script
# ==============================================================================
# Maps IPv6 neighbor cache entries to hostnames by cross-referencing
# MAC addresses with DHCPv4 lease names. Only maps global-scope (GUA)
# addresses, skipping link-local (fe80::) and deprecated addresses.
# Runs via cron every 2 minutes: */2 * * * * /root/sync_ipv6_hosts.sh
# ==============================================================================

TMP_FILE="/tmp/hosts/ipv6_slaac.tmp"
FINAL_FILE="/tmp/hosts/ipv6_slaac"

# Ensure the directory exists
mkdir -p /tmp/hosts

> "$TMP_FILE"

# Parse IPv6 neighbor cache — only REACHABLE/STALE entries with global scope
ip -6 neigh show dev br-lan | grep lladdr | while read -r IP _ MAC _; do
    [ -z "$MAC" ] && continue

    # Skip link-local addresses (fe80::) — not useful for DNS resolution
    case "$IP" in
        fe80:*|fd*) continue ;;
    esac

    # Find hostname in IPv4 DHCP leases matching this MAC
    HOSTNAME=$(awk -v mac="$MAC" 'tolower($2) == tolower(mac) {print $4}' /tmp/dhcp.leases | head -n 1)

    if [ -n "$HOSTNAME" ] && [ "$HOSTNAME" != "*" ]; then
        echo "$IP $HOSTNAME.lan $HOSTNAME" >> "$TMP_FILE"
    fi
done

# Deduplicate: keep only the shortest IPv6 address per hostname
# Shorter addresses (e.g., ::100) are typically stable EUI-64/SLAAC addresses,
# while longer ones (e.g., ::b4bc:49f1:6461:5df6) are privacy extensions.
awk '!seen[$2]++ { print }' "$TMP_FILE" | sort > "${TMP_FILE}.dedup"
mv "${TMP_FILE}.dedup" "$TMP_FILE"

# Only reload dnsmasq if the file actually changed
if ! cmp -s "$TMP_FILE" "$FINAL_FILE"; then
    mv "$TMP_FILE" "$FINAL_FILE"
    killall -SIGHUP dnsmasq >/dev/null 2>&1
else
    rm -f "$TMP_FILE"
fi
