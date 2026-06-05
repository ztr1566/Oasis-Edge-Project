#!/bin/sh
# ==============================================================================
# IPv6 Client Viewer — Show connected devices with their IPv6 addresses
# ==============================================================================
# Displays a formatted table of LAN clients with their global IPv6 addresses
# resolved from the neighbor cache, cross-referenced with DHCPv4 hostnames.
# Skips link-local (fe80::) addresses for cleaner output.
# ==============================================================================

printf "%-25s %-45s %s\n" "HOSTNAME" "IPV6 ADDRESS" "MAC ADDRESS"
printf "%-25s %-45s %s\n" "--------" "------------" "-----------"

ip -6 neigh show dev br-lan | grep lladdr | while read -r IP _ MAC _; do
    [ -z "$MAC" ] && continue

    # Skip link-local addresses — not useful for client identification
    case "$IP" in
        fe80:*) continue ;;
    esac

    # Find hostname in IPv4 DHCP leases matching this MAC
    HOSTNAME=$(awk -v mac="$MAC" 'tolower($2) == tolower(mac) {print $4}' /tmp/dhcp.leases | head -n 1)

    [ -z "$HOSTNAME" ] && HOSTNAME="Unknown"

    printf "%-25s %-45s %s\n" "$HOSTNAME" "$IP" "$MAC"
done | sort
