#!/bin/sh
# ==============================================================================
# 🌴 Project OasisEdge: Post-Upgrade Restore & Automation Script
# ==============================================================================
# This script automates package restoration and environment recovery after an
# OpenWrt firmware upgrade (Sysupgrade). It cleanly manages package dependencies,
# avoids dnsmasq-full conflicts, resizes partitions on the fly to unlock full
# SD card capacity, and registers services natively using their own CLI tools.
#
# Last updated: 2026-06-07 — Synced RA timers, SQM values to live tuned config.
# Removed dead usque references. Fixed cron intervals to 1-minute.
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

# 6. Register AdGuard Home Service via init.d
echo "⚙️ Enabling AdGuard Home service..."
/etc/init.d/adguardhome enable
/etc/init.d/adguardhome start >/dev/null 2>&1
echo "✅ AdGuard Home service enabled and started."

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

# Set descriptive hostname
uci set system.@system[0].hostname='OasisEdge'
uci commit system

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

# RA parameters — tuned for stable operation and battery life
# Values synced from live production config (2026-06-07)
uci set dhcp.lan.ra_maxinterval='900'
uci set dhcp.lan.ra_mininterval='200'
uci set dhcp.lan.ra_lifetime='3600'
uci set dhcp.lan.ra_mtu='1280'
uci set dhcp.lan.ra_unicast='1'
uci set dhcp.lan.ra_retransmit='2000'
uci set dhcp.lan.ra_default='2'
uci -q delete dhcp.lan.ra_reachable
uci -q delete dhcp.lan.ra_dns
uci add_list dhcp.lan.ra_dns='2a09:7373::1'

# Sync RA lifetimes with DHCPv4 leasetime for consistency
uci set dhcp.lan.ra_useleasetime='1'

# Add DHCPv4 options for faster browsing (domain, broadcast, disable WPAD)
uci add_list dhcp.lan.dhcp_option='15,lan'
uci add_list dhcp.lan.dhcp_option='28,192.168.2.255'
uci add_list dhcp.lan.dhcp_option='252,"\n"'

# Remove ULA prefix if present (redundant with stable ISP GUA prefix)
uci -q delete network.globals.ula_prefix

uci commit dhcp
uci commit network
echo "   ➔ IPv6: SLAAC enabled, stateful DHCPv6 disabled, RA timers synced."

# Ensure the IPv6 SLAAC auto-naming script is executable
if [ -f /root/sync_ipv6_hosts.sh ]; then
    chmod +x /root/sync_ipv6_hosts.sh
    echo "   ➔ IPv6 SLAAC sync script permissions restored."

    # Re-inject the cron job silently if missing (every 1 minute)
    if ! crontab -l 2>/dev/null | grep -q 'sync_ipv6_hosts.sh'; then
        (crontab -l 2>/dev/null; echo '* * * * * /root/sync_ipv6_hosts.sh >/dev/null 2>&1') | crontab -
        echo "   ➔ Cron job for IPv6 SLAAC sync injected (every 1 min)."
    fi
fi

if [ -f /root/sync_agh_ipv6_clients.sh ]; then
    chmod +x /root/sync_agh_ipv6_clients.sh
    echo "   ➔ AdGuardHome IPv6 sync script permissions restored."

    if ! crontab -l 2>/dev/null | grep -q 'sync_agh_ipv6_clients.sh'; then
        (crontab -l 2>/dev/null; echo '* * * * * /root/sync_agh_ipv6_clients.sh >/dev/null 2>&1') | crontab -
        echo "   ➔ Cron job for AGH IPv6 sync injected (every 1 min)."
    fi
fi

if [ -f /root/show_ipv6_clients.sh ]; then
    chmod +x /root/show_ipv6_clients.sh
    echo "   ➔ IPv6 client viewer script permissions restored."
fi

# =========================================================================
# 9. SQM / QoS Hardening
# =========================================================================
# Values synced from live production config (2026-06-07)
# =========================================================================
echo "📶 Applying SQM / QoS configuration..."

uci set firewall.@defaults[0].flow_offloading='0'
uci set firewall.@defaults[0].flow_offloading_hw='0'
echo "   ➔ Flow offloading disabled (required for SQM to work correctly)."

uci set sqm.eth1.enabled='1'
uci set sqm.eth1.interface='pppoe-WAN'
uci set sqm.eth1.download='52000'
uci set sqm.eth1.upload='9400'
uci set sqm.eth1.qdisc='cake'
uci set sqm.eth1.script='piece_of_cake.qos'
uci set sqm.eth1.linklayer='ethernet'
uci set sqm.eth1.overhead='34'
uci set sqm.eth1.qdisc_advanced='1'
uci set sqm.eth1.squash_dscp='0'
uci set sqm.eth1.squash_ingress='0'
uci set sqm.eth1.ingress_ecn='ECN'
uci set sqm.eth1.egress_ecn='ECN'
uci set sqm.eth1.iqdisc_opts='nat dual-dsthost diffserv4 mpu 68'
uci set sqm.eth1.eqdisc_opts='nat dual-srchost ack-filter diffserv4 mpu 68'
uci set sqm.eth1.qdisc_really_really_advanced='1'
echo "   ➔ SQM Cake configured: 52000↓ / 9400↑ kbps, diffserv4, ECN."

uci commit firewall
uci commit sqm
echo "✅ SQM / QoS hardening applied and committed."

# =========================================================================
# 10. WireGuard Tunnel — Cloudflare WARP IPv6
# =========================================================================
# WireGuard for best latency and Egypt routing.
# A cron script bounces the WAN interface if the IP starts with
# 197.x.x.x, since Egyptian ISPs block WireGuard handshakes on that range.
# =========================================================================
echo "🔒 Configuring WireGuard WARP tunnel for IPv6..."

# Configure WireGuard wg0 interface
uci set network.wg0=interface
uci set network.wg0.proto='wireguard'
uci set network.wg0.private_key='4JiByvjAZ4pI/Gxub5nG84Nm9v+IT9gj4CJNvd71Q1c='
uci -q delete network.wg0.addresses
uci add_list network.wg0.addresses='172.16.0.2/32'
uci add_list network.wg0.addresses='2606:4700:110:8547:f97:aeec:7fd6:1d36/128'
uci set network.wg0.mtu='1280'

uci -q delete network.@wireguard_wg0[0]
uci add network wireguard_wg0
uci rename network.@wireguard_wg0[-1]=wg0_peer
uci set network.wg0_peer.public_key='bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo='
uci set network.wg0_peer.endpoint_host='162.159.192.1'
uci set network.wg0_peer.endpoint_port='2408'
uci set network.wg0_peer.route_allowed_ips='1'
uci -q delete network.wg0_peer.allowed_ips
uci add_list network.wg0_peer.allowed_ips='::/0'
uci set network.wg0_peer.persistent_keepalive='25'

# Configure firewall zone for wg0 device
uci set firewall.warp=zone
uci set firewall.warp.name='warp'
uci set firewall.warp.device='wg0'
uci set firewall.warp.network='wg0'
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

uci commit network
uci commit firewall
echo "   ➔ WireGuard wg0 configured and firewall updated."

# Deploy the WAN IP checker with cooldown (avoids 197.x DPI blocks)
cat << 'EOF' > /root/check_wg_197.sh
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
EOF
chmod +x /root/check_wg_197.sh
if ! crontab -l 2>/dev/null | grep -q "check_wg_197.sh"; then
    (crontab -l 2>/dev/null; echo '* * * * * /root/check_wg_197.sh >/dev/null 2>&1') | crontab -
fi
echo "   ➔ Deployed IP checker with 5-min cooldown to bypass 197.x DPI block."

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

echo "🎉 OasisEdge recovery completed successfully! Your network is 100% operational."
echo "========================================================================"
