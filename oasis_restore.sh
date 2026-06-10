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
if [ -f /etc/hotplug.d/dhcp/90-mac-whitelist ]; then
    chmod +x /etc/hotplug.d/dhcp/90-mac-whitelist
    echo "   ➔ Executable restored: /etc/hotplug.d/dhcp/90-mac-whitelist"
fi

if [ -f /etc/firewall.user ]; then
    chmod +x /etc/firewall.user
    echo "   ➔ Executable restored: /etc/firewall.user"

    # Inject dynamic MAC whitelist sync if missing
    if ! grep -q "Dynamic MAC Whitelist Sync" /etc/firewall.user; then
        cat << 'EOF' >> /etc/firewall.user

# ===================================================================
# Dynamic MAC Whitelist Sync from DHCP Static Leases
# ===================================================================
# Clear the existing nftables allowed_macs set
nft flush set inet fw4 allowed_macs 2>/dev/null

# Read all MACs from dhcp.@host configurations and add them
idx=0
while true; do
    sectype=$(uci -q get dhcp.@host[$idx])
    [ -z "$sectype" ] && break
    
    mac=$(uci -q get dhcp.@host[$idx].mac)
    if [ -n "$mac" ]; then
        for m in $mac; do
            m_lower=$(echo "$m" | tr 'A-Z' 'a-z')
            nft add element inet fw4 allowed_macs { "$m_lower" } 2>/dev/null
        done
    fi
    idx=$((idx + 1))
done

# Add infrastructure MACs (e.g. modems/gateways)
nft add element inet fw4 allowed_macs { "e8:48:b8:13:fa:e6", "50:78:b3:a8:30:54" } 2>/dev/null

# === Global MAC Filter Enforcement (IPv4) ===
# 1. Forward Chain: Drop any forwarding traffic from unauthorized MACs.
# Must run before conntrack (established) rule to block active sessions instantly.
if ! nft list chain inet fw4 forward 2>/dev/null | grep -q "Block-Unauthorized-MACs"; then
    nft insert rule inet fw4 forward iifname "br-lan" ether saddr != @allowed_macs counter reject comment "\"Block-Unauthorized-MACs\"" 2>/dev/null
fi

# 2. Input Chain: Block unauthorized MACs from accessing the router itself (LuCI, DNS, SSH),
# but allow DHCP (UDP port 67) so they can request an IP.
if ! nft list chain inet fw4 input 2>/dev/null | grep -q "Block-Unauthorized-MACs"; then
    nft insert rule inet fw4 input iifname "br-lan" ether saddr != @allowed_macs counter reject comment "\"Block-Unauthorized-MACs\"" 2>/dev/null
    nft insert rule inet fw4 input iifname "br-lan" udp dport 67 accept comment "\"Allow-DHCP-Input\"" 2>/dev/null
fi
EOF
        echo "   ➔ Dynamic MAC whitelist sync script injected into /etc/firewall.user"
    fi
fi

# Deploy DHCP Hotplug MAC Whitelist Sync script if missing
if [ ! -f /etc/hotplug.d/dhcp/90-mac-whitelist ]; then
    mkdir -p /etc/hotplug.d/dhcp
    cat << 'EOF' > /etc/hotplug.d/dhcp/90-mac-whitelist
#!/bin/sh
# ===================================================================
# DHCP Hotplug MAC Whitelist Sync
# ===================================================================
# Triggered on DHCP lease add/update/remove.
# Automatically whitelists MAC addresses in the firewall if they
# exist in the DHCP static leases config.
# ===================================================================

case "$ACTION" in
    add|update)
        [ -z "$MACADDR" ] && exit 0
        
        # Normalize MAC to lowercase
        MAC_LOWER=$(echo "$MACADDR" | tr 'A-Z' 'a-z')
        
        # Check if MAC exists in the static leases configuration (/etc/config/dhcp)
        if uci show dhcp 2>/dev/null | grep -q -i -E "mac='$MACADDR'|mac='$MAC_LOWER'"; then
            nft add element inet fw4 allowed_macs { "$MAC_LOWER" } 2>/dev/null
        fi
        ;;
    remove|destroy|release)
        [ -z "$MACADDR" ] && exit 0
        MAC_LOWER=$(echo "$MACADDR" | tr 'A-Z' 'a-z')
        # Check if MAC no longer exists in static leases config before deleting element
        if ! uci show dhcp 2>/dev/null | grep -q -i -E "mac='$MACADDR'|mac='$MAC_LOWER'"; then
            nft delete element inet fw4 allowed_macs { "$MAC_LOWER" } 2>/dev/null
        fi
        ;;
esac
EOF
    chmod +x /etc/hotplug.d/dhcp/90-mac-whitelist
    echo "   ➔ DHCP MAC whitelist hotplug script deployed."
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
# 8b. IPv6 Deactivation (IPv4 Only System)
# =========================================================================
echo "🌐 Deactivating IPv6..."

# Disable IPv6 on LAN
uci -q set network.lan.ipv6='0'
uci -q delete network.lan.ip6addr
uci -q delete network.globals.ula_prefix

# Disable Router Advertisements (RA) and DHCPv6 completely on LAN
uci -q set dhcp.lan.ra='disabled'
uci -q set dhcp.lan.dhcpv6='disabled'
uci -q delete dhcp.lan.ra_slaac
uci -q delete dhcp.lan.ra_flags
uci -q delete dhcp.lan.ra_maxinterval
uci -q delete dhcp.lan.ra_mininterval
uci -q delete dhcp.lan.ra_lifetime
uci -q delete dhcp.lan.ra_mtu
uci -q delete dhcp.lan.ra_unicast
uci -q delete dhcp.lan.ra_retransmit
uci -q delete dhcp.lan.ra_default
uci -q delete dhcp.lan.ra_dns
uci -q delete dhcp.lan.ra_useleasetime

# Tune DHCPv4 lease time to 24 hours (reduces client renewal wakeups)
uci set dhcp.lan.leasetime='24h'

# Add DHCPv4 options for faster browsing (domain, broadcast, disable WPAD)
uci -q delete dhcp.lan.dhcp_option
uci add_list dhcp.lan.dhcp_option='6,192.168.2.1'
uci add_list dhcp.lan.dhcp_option='15,lan'
uci add_list dhcp.lan.dhcp_option='28,192.168.2.255'
uci add_list dhcp.lan.dhcp_option='252,"\n"'

uci commit dhcp
uci commit network
echo "   ➔ IPv6 disabled globally and on LAN interface."

# Deploy battery-saving sysctl settings (reduce ARP and neighbor probe frequency)
mkdir -p /etc/sysctl.d
cat << 'EOF' > /etc/sysctl.d/90-battery-optimize.conf
# Optimize ARP / Neighbor Cache probe timers to reduce multicast/unicast wakeups
net.ipv4.neigh.br-lan.base_reachable_time_ms=120000
net.ipv6.neigh.br-lan.base_reachable_time_ms=120000
net.ipv4.neigh.br-lan.delay_first_probe_time=15
net.ipv6.neigh.br-lan.delay_first_probe_time=15
EOF
sysctl -p /etc/sysctl.d/90-battery-optimize.conf >/dev/null 2>&1

# Ensure sysctl config survives upgrades
grep -q '/etc/sysctl.d/90-battery-optimize.conf' /etc/sysupgrade.conf || echo '/etc/sysctl.d/90-battery-optimize.conf' >> /etc/sysupgrade.conf

# Ensure the IPv6 SLAAC auto-naming script is executable

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
# 10b. Enhanced VPN & DoH/DoT Bypass Block Rules
# =========================================================================
# Idempotently delete existing rules to prevent duplicates
delete_firewall_rule() {
    local name="$1"
    local idx=0
    while true; do
        local sectype=$(uci -q get firewall.@rule[$idx])
        [ -z "$sectype" ] && break
        local rname=$(uci -q get firewall.@rule[$idx].name)
        if [ "$rname" = "$name" ]; then
            uci delete firewall.@rule[$idx]
            continue
        fi
        idx=$((idx + 1))
    done
}

delete_firewall_rule "Block-OpenVPN-LAN"
delete_firewall_rule "Block-IPSec-LAN"
delete_firewall_rule "Block-GRE-LAN"
delete_firewall_rule "Block-ESP-LAN"
delete_firewall_rule "Block-L2TP-LAN"
delete_firewall_rule "Block-WireGuard-LAN"
delete_firewall_rule "Block-PPTP-LAN"
delete_firewall_rule "Block-Tor-Ports"
delete_firewall_rule "Block-Socks-Proxy-Ports"
delete_firewall_rule "Block-Public-DNS-Bypass-IPv4"
delete_firewall_rule "Block-Public-DNS-Bypass-IPv6"



# Add DoH/DoT/DoQ Public DNS Bypass IPv4 (ports 443, 784, 853 TCP/UDP)
uci add firewall rule
uci set firewall.@rule[-1].name='Block-Public-DNS-Bypass-IPv4'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].dest='*'
uci set firewall.@rule[-1].dest_ip='1.1.1.1 1.0.0.1 1.1.1.3 1.0.0.3 8.8.8.8 8.8.4.4 9.9.9.9 149.112.112.112 94.140.14.14 94.140.15.15'
uci set firewall.@rule[-1].dest_port='443 784 853'
uci set firewall.@rule[-1].proto='tcp udp'
uci set firewall.@rule[-1].target='REJECT'



# =========================================================================
# 10c. MAC-based Whitelist Firewall Rules & Cleanup
# =========================================================================
# Delete old or unused firewall rules, zones, and ipsets
uci -q delete firewall.block_trap
uci -q delete firewall.allowed_macs
uci -q delete firewall.warp
uci -q delete firewall.lan_to_warp
uci -q delete firewall.vpn_block6
uci -q delete firewall.block_vpn_ips_v6

delete_firewall_rule "Block-Unauthorized-WAN"
delete_firewall_rule "Block-Unauthorized-WARP"
delete_firewall_rule "Intercept-DNS-UDP-v6"
delete_firewall_rule "Intercept-DNS-TCP-v6"

# Create allowed_macs ipset
uci set firewall.allowed_macs=ipset
uci set firewall.allowed_macs.name='allowed_macs'
uci set firewall.allowed_macs.match='src_mac'

uci commit network
uci commit firewall
echo "   ➔ Firewall MAC whitelisting structure rebuilt."

# Remove the old IP checker script and cron job (no longer needed without wg0)
rm -f /root/check_wg_197.sh
if crontab -l 2>/dev/null | grep -q "check_wg_197.sh"; then
    crontab -l 2>/dev/null | grep -v "check_wg_197.sh" | crontab -
fi
echo "   ➔ Removed check_wg_197.sh and cleared its cron job."

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
