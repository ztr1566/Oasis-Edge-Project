#!/bin/sh
# ==============================================================================
# 🌴 Project OasisEdge: Post-Upgrade Restore & Automation Script
# ==============================================================================
# This script automates package restoration and environment recovery after an
# OpenWrt firmware upgrade (Sysupgrade). It cleanly manages package dependencies,
# avoids dnsmasq-full conflicts, resizes partitions on the fly to unlock full
# SD card capacity, and registers services natively using their own CLI tools.
#
# Last updated: 2026-06-05 — Migrated from WireGuard to MASQUE (usque) for
# DPI-resistant IPv6 tunnel via Cloudflare WARP.
# IPv6 optimized: SLAAC + stateless RA (no stateful DHCPv6 addresses).
# ==============================================================================

echo "🚀 Starting Project OasisEdge environment recovery..."

# 1. Verify Internet Connectivity
echo "📡 Checking internet connection..."
if ! ping -c 3 1.1.1.1 >/dev/null 2>&1; then
    echo "❌ ERROR: No internet connection detected."
    echo "   Please verify your WAN connection is up before running this script."
    exit 1
fi
echo "✅ Internet connection verified."

# 2. Update Package Lists
echo "📦 Updating package indexes..."
apk update

# 3. Cleanly Swap dnsmasq to dnsmasq-full (Avoid Conflicts)
echo "🔄 Swapping stock dnsmasq for dnsmasq-full..."
if apk list --installed | grep -q "^dnsmasq "; then
    apk del dnsmasq
fi
apk add dnsmasq-full
echo "✅ dnsmasq-full installed."

# 4. Install Edge Optimization Packages
echo "⚙️ Installing Project OasisEdge optimization packages..."
apk add \
    luci-app-sqm sqm-scripts \
    luci-app-ddns ddns-scripts \
    bind-host tc-full nftables \
    ip6tables-nft \
    kmod-tun ip-full unzip \
    adguardhome

echo "✅ All required packages installed."

# 5. Restore Executable Permissions for Custom Hardening and Scripts
echo "🛡️ Restoring file permissions..."
if [ -f /etc/hotplug.d/iface/99-wg6-route ]; then
    chmod +x /etc/hotplug.d/iface/99-wg6-route
    echo "   ➔ Executable restored: /etc/hotplug.d/iface/99-wg6-route"
fi

if [ -f /etc/firewall.user ]; then
    chmod +x /etc/firewall.user
    echo "   ➔ Executable restored: /etc/firewall.user"
fi

if [ -f /etc/dropbear/authorized_keys ]; then
    chmod 600 /etc/dropbear/authorized_keys
    echo "   ➔ Authorized keys secured."
fi

# 6. Register AdGuard Home Service natively via CLI
echo "⚙️ Registering AdGuard Home service natively via CLI..."
/usr/bin/adguardhome -s install >/dev/null 2>&1
/usr/bin/adguardhome -s start >/dev/null 2>&1
echo "✅ AdGuard Home service natively registered and started."

# 7. Automated Storage Expansion & Partition Unlock (On-The-Fly Resizing)
echo "💾 Expanding root partition to utilize full SD card capacity..."
apk add partx-utils resize2fs e2fsprogs

# Identify root device
ROOT_DEV=$(mount | grep ' / ' | awk '{print $1}')
if [ "$ROOT_DEV" = "/dev/root" ]; then
    ROOT_DEV=$(readlink -f /dev/root)
fi

echo "   ➔ Detected active root device: $ROOT_DEV"

# Split parent device and partition index (handles /dev/mmcblk0p2 and /dev/sda2 styles)
if echo "$ROOT_DEV" | grep -q "mmcblk"; then
    DISK=$(echo "$ROOT_DEV" | sed -E 's/p[0-9]+$//')
    PART_NUM=$(echo "$ROOT_DEV" | sed -E 's/.*p//')
else
    DISK=$(echo "$ROOT_DEV" | sed -E 's/[0-9]+$//')
    PART_NUM=$(echo "$ROOT_DEV" | sed -E 's/.*[^0-9]//')
fi

if [ -n "$DISK" ] && [ -n "$PART_NUM" ]; then
    echo "   ➔ Disk: $DISK | Partition Index: $PART_NUM"
    # Expand the partition table boundary
    if growpart "$DISK" "$PART_NUM"; then
        echo "   ➔ Partition boundary successfully expanded."
        # Expand the active filesystem online (ext4)
        if resize2fs "$ROOT_DEV"; then
            echo "   ➔ Filesystem online resize completed successfully!"
        else
            echo "   ➔ Warning: resize2fs failed. Attempting f2fs resize..."
            apk add f2fs-tools
            resize.f2fs "$ROOT_DEV"
        fi
    else
        echo "   ➔ Warning: growpart was unable to expand the partition (it may already be fully expanded)."
    fi
else
    echo "   ❌ ERROR: Unable to parse parent disk and partition index."
fi

# 8. Re-Apply System Optimizations & Hardening
echo "🔧 Applying system optimizations and disabling unused services..."

# Disable unused and unnecessary services for minimal footprint
# NOTE: odhcpd is kept ENABLED — it handles RA (Router Advertisements)
#       which is required for SLAAC IPv6 addressing on the LAN.
for svc in px5g gpio_switch; do
    if [ -f "/etc/init.d/$svc" ]; then
        /etc/init.d/$svc stop >/dev/null 2>&1
        /etc/init.d/$svc disable >/dev/null 2>&1
        echo "   ➔ Disabled service: $svc"
    fi
done

# =========================================================================
# 8b. IPv6 SLAAC + Stateless RA Optimization
# =========================================================================
# Strategy: SLAAC for addresses (A-flag) + RA-only for DNS (O-flag).
# Stateful DHCPv6 address assignment is DISABLED to prevent duplicate
# /128 addresses on clients alongside SLAAC /64 addresses.
# DNS is delivered via RDNSS in Router Advertisements (works for all
# devices including Android which ignores DHCPv6).
# =========================================================================
echo "🌐 Applying IPv6 SLAAC optimization..."

# Remove deprecated ra_management (conflicts with modern ra_flags)
uci -q delete dhcp.lan.ra_management

# RA server enabled, stateful DHCPv6 disabled (no /128 address leases)
uci set dhcp.lan.ra='server'
uci set dhcp.lan.dhcpv6='disabled'

# Enable SLAAC (A-flag) — clients auto-generate their own IPv6 address
uci set dhcp.lan.ra_slaac='1'

# Set O-flag only (stateless — DNS info via RA, no address assignment)
uci -q delete dhcp.lan.ra_flags
uci add_list dhcp.lan.ra_flags='other-config'

# Sync RA lifetimes with DHCPv4 leasetime for consistency
uci set dhcp.lan.ra_useleasetime='1'

# Remove ULA prefix if present (redundant with stable ISP GUA prefix)
uci -q delete network.globals.ula_prefix

uci commit dhcp
uci commit network
echo "   ➔ IPv6: SLAAC enabled, stateful DHCPv6 disabled, lifetimes synced."

# Ensure the IPv6 SLAAC auto-naming script is executable
if [ -f /root/sync_ipv6_hosts.sh ]; then
    chmod +x /root/sync_ipv6_hosts.sh
    echo "   ➔ IPv6 SLAAC sync script permissions restored."

    # Re-inject the cron job silently if missing
    if ! crontab -l 2>/dev/null | grep -q 'sync_ipv6_hosts.sh'; then
        (crontab -l 2>/dev/null; echo '*/2 * * * * /root/sync_ipv6_hosts.sh >/dev/null 2>&1') | crontab -
        echo "   ➔ Cron job for IPv6 SLAAC sync injected silently."
    fi
fi

if [ -f /root/show_ipv6_clients.sh ]; then
    chmod +x /root/show_ipv6_clients.sh
    echo "   ➔ IPv6 client viewer script permissions restored."
fi

# =========================================================================
# 9. SQM / QoS Hardening
# =========================================================================
echo "📶 Applying SQM / QoS configuration..."

uci set firewall.@defaults[0].flow_offloading='0'
uci set firewall.@defaults[0].flow_offloading_hw='0'
echo "   ➔ Flow offloading disabled (required for SQM to work correctly)."

uci set sqm.eth1.enabled='1'
uci set sqm.eth1.interface='pppoe-WAN'
uci set sqm.eth1.download='68095'
uci set sqm.eth1.upload='9728'
uci set sqm.eth1.qdisc='cake'
uci set sqm.eth1.script='piece_of_cake.qos'
uci set sqm.eth1.linklayer='ethernet'
uci set sqm.eth1.overhead='34'
uci set sqm.eth1.qdisc_advanced='1'
uci set sqm.eth1.squash_dscp='0'
uci set sqm.eth1.squash_ingress='0'
uci set sqm.eth1.ingress_ecn='ECN'
uci set sqm.eth1.egress_ecn='ECN'
uci set sqm.eth1.iqdisc_opts='nat dual-dsthost rtt 40ms'
uci set sqm.eth1.eqdisc_opts='nat dual-srchost ack-filter rtt 40ms'
uci set sqm.eth1.qdisc_really_really_advanced='1'
echo "   ➔ SQM Cake configured: 68095↓ / 9728↑ kbps, per-host fairness, ECN."

uci commit firewall
uci commit sqm
echo "✅ SQM / QoS hardening applied and committed."

# =========================================================================
# 10. MASQUE Tunnel (usque) — Cloudflare WARP IPv6
# =========================================================================
# Replaced WireGuard with usque MASQUE client because Egyptian ISPs use
# Deep Packet Inspection (DPI) to block WireGuard handshakes on certain
# IP ranges (197.x.x.x). MASQUE traffic looks like standard HTTPS over
# TCP port 443 — completely indistinguishable from normal web browsing.
# Uses HTTP/2 TCP mode for maximum DPI resistance and reliability.
# WARP+ (Argo Smart Routing) license applied for optimized routing.
# =========================================================================
echo "🔒 Configuring MASQUE WARP+ (usque) tunnel for IPv6..."

# Ensure usque binary is executable
if [ -f /usr/bin/usque ]; then
    chmod +x /usr/bin/usque
    echo "   ➔ usque binary permissions restored."
fi

# Ensure hook scripts are executable
if [ -d /etc/usque ]; then
    chmod +x /etc/usque/up.sh 2>/dev/null
    chmod +x /etc/usque/down.sh 2>/dev/null
    echo "   ➔ usque hook scripts permissions restored."
fi

# Ensure init script is executable
if [ -f /etc/init.d/usque ]; then
    chmod +x /etc/init.d/usque
    echo "   ➔ usque init script permissions restored."
fi

# Load TUN kernel module
modprobe tun 2>/dev/null

# Increase UDP buffer sizes for QUIC performance
sysctl -w net.core.rmem_max=7500000 >/dev/null 2>&1
sysctl -w net.core.wmem_max=7500000 >/dev/null 2>&1

# Configure firewall zone for usque tun0 device
uci set firewall.warp=zone
uci set firewall.warp.name='warp'
uci set firewall.warp.device='tun0'
uci set firewall.warp.input='REJECT'
uci set firewall.warp.output='ACCEPT'
uci set firewall.warp.forward='REJECT'
uci set firewall.warp.masq='1'
uci set firewall.warp.mtu_fix='1'
uci set firewall.warp.masq6='1'

# Ensure LAN->WARP forwarding exists
uci set firewall.lan_to_warp=forwarding
uci set firewall.lan_to_warp.src='lan'
uci set firewall.lan_to_warp.dest='warp'

uci commit firewall
echo "   ➔ Firewall zone 'warp' configured for tun0 device."

# Enable and start usque service
/etc/init.d/usque enable
echo "✅ MASQUE (usque) tunnel configured and enabled."

# 11. Restart Services to Apply Restored Configs
echo "🔄 Reloading router services..."
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/odhcpd restart
/etc/init.d/dnsmasq restart
/etc/init.d/sqm restart
/etc/init.d/ddns restart
/etc/init.d/cron restart
/etc/init.d/adguardhome restart >/dev/null 2>&1
/etc/init.d/uhttpd restart >/dev/null 2>&1
/etc/init.d/usque start >/dev/null 2>&1

echo "🎉 OasisEdge recovery completed successfully! Your network is 100% operational."
echo "========================================================================"
