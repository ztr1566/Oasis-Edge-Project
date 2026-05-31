# 👣 Project OasisEdge: Chronological Setup Steps Guide

This document provides a step-by-step chronological setup guide to reproduce **Project OasisEdge**—your fully optimized, dual-stack, privacy-first OpenWrt gateway on the OrangePi Zero 3. 

It is designed to be highly educational. In addition to the copy-paste commands, each phase includes an advanced callout explaining exactly **why** we perform each configuration and optimization, with specific technical focuses on the challenges of operating a dual-stack home network in **Egypt** (where ISPs do not support native IPv6, and absolute privacy from ISP logging is paramount).

---

## 📋 Prerequisites & Hardware List
*   **Single Board Computer:** OrangePi Zero 3 (2 GB RAM variant) — *While we are not stacking with this specific hardware, ensure your router has at least 1 GB of RAM (can be Raspberry Pi or Orange Pi).*
*   **Power Supply:** 5V 3A USB-C power adapter.
*   **Storage:** 32 GB or 64 GB MicroSD card. *(The most important thing is to be Application Class 2 (A2) rather than A1 to ensure high random read/write durability under OS logs and DB loads).*
*   **Software Tools:** BalenaEtcher or Rufus (for GUI flashing), SSH Client (PuTTY or Linux Terminal).
*   **Operating System Image:** OpenWrt 25.12.4 Cortex-A53 stable image.

---

## 🏁 Phase 1: Flashing & Initial Connection

```
  [ Flash MicroSD ] ──> [ Boot Orange Pi ] ──> [ SSH to 192.168.2.1 ] ──> [ Set Root Password ]
```

1.  **Flash the OS:**
    *   Download the OpenWrt Cortex-A53 stable firmware image.
    *   **GUI Method:** Insert the MicroSD card into your computer, open **BalenaEtcher**, select the OpenWrt image, select your MicroSD card, and click **Flash**.
    *   **Linux CLI Method (using `dd`):**
        Identify your SD card device path (e.g., `/dev/sdX` or `/dev/mmcblkX` using `lsblk`), unmount any mounted partitions, and execute:
        ```bash
        sudo dd if=openwrt-image.img of=/dev/sdX bs=4M status=progress conv=fsync
        ```
        > [!CAUTION]
        > Double-check your target device path (`of=/dev/sdX`) to prevent accidentally overwriting your system or boot drives!

    > [!TIP]
    > **Why the SD Card must be A2 (Application Class 2):**
    > OpenWrt does not just run in RAM; it writes logs, DHCP leases, and reads configuration data from the SD card. An **A2 class** SD card features high random Read/Write operations per second (IOPS) and built-in controller caching. This prevents the filesystem from bottlenecking or corrupting under continuous system and database writes, guaranteeing router longevity and stability for years.

2.  **Initial Boot:**
    *   Insert the flashed MicroSD card into the OrangePi.
    *   Connect the Ethernet port of the OrangePi to your computer or switch.
    *   Power on the OrangePi Zero 3.
3.  **SSH Connection:**
    *   The router defaults to IP `192.168.1.1` (or `192.168.2.1` depending on custom images). 
    *   Open your terminal and SSH into the router:
        ```bash
        ssh root@192.168.2.1
        ```
    *   Set a secure root password:
        ```bash
        passwd
        ```

---

## 🔌 Phase 1.5: Upstream ISP Router Configuration (Bridge & Access Point Modes)

To ensure OpenWrt handles all traffic shaping, security layers, and DNS encryption cleanly without double-NAT interference, your regular ISP router must be configured correctly. While these steps target the **TP-Link Archer VR600 V3** (VDSL/ADSL gateway), they apply universally to all standard ISP routers.

### Option A: Bridge Mode (Recommended for Double-NAT Elimination)
This disables the routing and DHCP capabilities of the ISP router, turning it into a pure transparent modem. OpenWrt will establish the PPPoE connection and receive the public IP address directly.

1.  **Access the ISP Router GUI:**
    *   Connect your computer directly to one of the VR600 V3's LAN ports (unconnected from OpenWrt).
    *   Open your browser and navigate to `http://192.168.1.1` and log in.
2.  **Delete the Default WAN Profile:**
    *   Navigate to **Advanced** (top tab) ➔ **Network** ➔ **WAN Settings** (left menu).
    *   Select the existing internet profile (PPPoE or Dynamic IP) and click **Delete**.
3.  **Create a Transparent Bridge Profile:**
    *   Click **Add** to create a new profile.
    *   **DSL Link Type:** Select `VDSL` or `ADSL` based on your physical broadband connection.
    *   **VLAN ID:** If your ISP requires VLAN tagging (e.g., Telecom Egypt often uses VLAN `50` or `51` for internet), check **Enable VLAN ID** and enter your ISP's tag.
    *   **Connection Type:** Select **Bridge** (or **Bridge Mode**).
    *   Click **Save** or **Apply**.
4.  **Disable DHCP, IGMP Snooping, & Keep Wi-Fi Active:**
    *   Navigate to **Advanced** ➔ **Network** ➔ **DHCP Server** and **uncheck** the **Enable** checkbox under DHCP Server to turn it off. Click **Save**. *This ensures the OpenWrt Orange Pi handles all local IP addresses, DHCP leases, and filtering.*
    *   Navigate to **Advanced** ➔ **Network** ➔ **LAN Settings** and **uncheck** **IGMP Snooping** (disable it) to prevent the VR600 V3 from filtering or blocking multicast packets. Click **Save**.
    *   **Keep Wi-Fi Enabled:** Do **not** disable the Wi-Fi. Ensure the 2.4 GHz and 5 GHz wireless networks are enabled and active on the VR600 V3. Since the wireless interface is bridged internally to the LAN switch, wireless clients will connect to the VR600's Wi-Fi but will receive their IP addresses, DNS resolution, and secure routing directly from the OpenWrt Orange Pi!
5.  **Cabling:** Connect an Ethernet cable from any **LAN** port of the bridged VR600 V3 to the physical LAN port of the OpenWrt router (`eth0`/`br-lan`).

---

### Option B: Repurposed Downstream Access Point (AP Mode Only)
If you want to reuse your VR600 V3's powerful Wi-Fi antennas to expand wireless coverage behind your OpenWrt gateway, configure it purely as a downstream Wi-Fi Access Point.

> [!IMPORTANT]
> **Division of Labor:** In this setup, the VR600 V3 is used **exclusively to provide Wi-Fi coverage for wireless clients**. All network routing, DNS filtering/resolution (via AdGuard Home), DHCP IP leasing, firewall parameters, and optimization layers are hosted and executed entirely by your central **Orange Pi (OpenWrt) gateway**.

1.  **Access settings:** Connect your computer directly to the VR600 V3 (disconnected from OpenWrt) and log in to `http://192.168.1.1`.
2.  **Change local IP address:**
    *   Navigate to **Advanced** ➔ **Network** ➔ **LAN Settings**.
    *   Change the IP address to a static address inside the OpenWrt subnet but outside the dynamic pool range (e.g., set to `192.168.2.2`).
    *   Click **Save** and allow the device to reboot. (You will access its interface at `http://192.168.2.2` in the future).
3.  **Disable DHCP Server & IGMP Snooping:**
    *   Log in to `http://192.168.2.2`.
    *   Navigate to **Advanced** ➔ **Network** ➔ **DHCP Server**.
    *   **Uncheck** **Enable** under DHCP Server to turn it off completely. Click **Save**.
    *   Navigate to **Advanced** ➔ **Network** ➔ **LAN Settings**.
    *   **Uncheck** **IGMP Snooping** (disable it) so that the AP does not filter out or block multicast discovery packets (e.g., Chromecast/mDNS sweeps), allowing OpenWrt's bridge to manage multicast routing cleanly. Click **Save**.
4.  **Connect LAN-to-LAN:**
    *   Connect an Ethernet cable from one of the **LAN** ports on OpenWrt to one of the **LAN** ports of the VR600 V3.
    > [!WARNING]
    > Do **not** connect the cable to the WAN port of the VR600 V3. By using a LAN-to-LAN connection, you bypass the VR600's internal routing stack and NAT, merging all wireless clients directly into OpenWrt's subnet and forwarding all their DNS queries to your local AdGuard Home resolver.

---

## 🌐 Phase 2: Dual-Stack Network Interfaces Setup

We will configure the network interfaces: LAN static IP, WAN PPPoE connection, and a secondary Modem access route.

1.  **Configure Network Interfaces:**
    Open `/etc/config/network` and configure the loopback, bridge LAN, PPPoE WAN, and static Modem access interfaces:
    ```ini
    config interface 'loopback'
            option device 'lo'
            option proto 'static'
            list ipaddr '127.0.0.1/8'

    config globals 'globals'
            option dhcp_default_duid 'YOUR_DHCP_DEFAULT_DUID'
            option packet_steering '2'

    config device
            option name 'br-lan'
            option type 'bridge'
            list ports 'eth0'
            option igmp_snooping '1'

    config interface 'lan'
            option device 'br-lan'
            option proto 'static'
            option ipv6 '0'
            list ipaddr '192.168.2.1/24'
            option multipath 'off'
            list ip6class 'local'
            option ip6addr '2a09:7373::1/64'

    config interface 'WAN'
            option proto 'pppoe'
            option device 'br-lan'
            option username 'YOUR_PPPOE_USERNAME'
            option password 'YOUR_PPPOE_PASSWORD'
            option ipv6 '0'
            option multipath 'off'
            option peerdns '0'
            list dns '127.0.0.1'
            list dns '1.1.1.1'

    config interface 'modem'
            option proto 'static'
            option device 'br-lan'
            option ipaddr '192.168.1.50'
            option netmask '255.255.255.0'
            option multipath 'off'
    ```
    > [!NOTE]
    > **Why the 'modem' interface is used (Connecting to your Upstream Modem):**
    > 1. **The Starting Point:** Initially, your physical DSL/Fiber modem was configured as the primary router, running on its own local network subnet (`192.168.1.0/24`) at IP address `192.168.1.1`.
    > 2. **The New Setup:** To prevent double-NAT (where two devices route traffic, causing lag and gaming issues), we put the physical modem into **Bridge Mode** (making it a transparent pass-through bridge) and made the new OpenWrt Orange Pi the main router, running on its own local subnet (`192.168.2.0/24`) at IP address `192.168.2.1`.
    > 3. **The Problem:** Once the modem is bridged, it no longer handles DHCP and is located on a different network subnet (`192.168.1.x`). Since your PC is on the `192.168.2.x` subnet, the OpenWrt router would normally forward any requests to `192.168.1.1` out to the PPPoE WAN interface, where the ISP would drop them. This makes your physical modem's admin console completely unreachable!
    > 4. **The Elegant Solution:** By adding the static `modem` interface with an IP of `192.168.1.50` on the local bridge (`br-lan`), we tell the OpenWrt kernel: *"You have a direct virtual foot in the modem's 192.168.1.0/24 network."* Now, whenever you type `192.168.1.1` into your browser, the router knows exactly how to forward that traffic directly to the physical modem's web UI. This allows you to check your line sync speed, connection logs, or diagnostic stats **without having to walk over, unplug cables, and plug your computer directly into the modem!**

    > [!TIP]
    > **Why Packet Steering (`packet_steering '2'`) is enabled:**
    > OpenWrt routers typically handle network traffic on a single CPU core. On small Single Board Computers like the Orange Pi Zero 3, high-speed NAT routing or PPPoE encryption can easily max out one core, causing packet loss and lag even if the other cores are idle. Packet Steering distributes packet-processing interrupts dynamically across all four CPU cores, maximizing throughput and routing performance.

    > [!IMPORTANT]
    > **Why Peer DNS (`peerdns '0'`) is disabled:**
    > By default, your ISP sends its own DNS servers when establishing the PPPoE connection. If `peerdns` remains enabled, the router's DNS configurations will be overridden by the ISP's DNS. Disabling this forces OpenWrt to ignore the ISP's DNS and query only the secure local loopback (`127.0.0.1` / AdGuard Home) and backups we defined. This ensures your DNS queries remain 100% encrypted, private, and blocked from ISP logging.

2.  **Apply Network Settings:**
    ```bash
    /etc/init.d/network restart
    ```

---

## 🛡️ Phase 3: Secure VPN Tunnels Configuration

We will set up the Cloudflare WARP tunnel (`wg0`) for IPv6 outbounds and the WireGuard Server (`wg1`) for remote clients.

1.  **Generate WireGuard Keys:**
    ```bash
    wg genkey | tee private.key | wg pubkey > public.key
    ```
2.  **Add Tunnels to `/etc/config/network`:**
    ```ini
    config interface 'wg0'
            option proto 'wireguard'
            option private_key 'YOUR_WARP_PRIVATE_KEY'
            list addresses '2606:4700:110:81e6::xxxx/128' # Your Cloudflare WARP IPv6 Address (masked)
            option multipath 'off'

    config wireguard_wg0 'wg0_peer'
            option interface 'wg0'
            option public_key 'bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo='
            option endpoint_host '188.114.97.170'
            option endpoint_port '500'
            option route_allowed_ips '1'
            option persistent_keepalive '25'
            list allowed_ips '::/0'

    config interface 'wg1'
            option proto 'wireguard'
            option private_key 'YOUR_SERVER_PRIVATE_KEY'
            option listen_port '51820'
            list addresses '10.9.0.1/24'

    config wireguard_wg1 'wg1_client1'
            option public_key 'CLIENT_PUBLIC_KEY'
            option preshared_key 'CLIENT_PRESHARED_KEY'
            option route_allowed_ips '1'
            list allowed_ips '10.9.0.2/32'
            option description 'Mobile_Client'
    ```
    > [!TIP]
    > **How Project OasisEdge Achieves Secure Dual-Stack IPv6 in Egypt:**
    > Because Egyptian ISPs strictly offer single-stack IPv4-only connectivity and native IPv6 is completely unavailable, we establish a secure WireGuard tunnel (`wg0`) to Cloudflare WARP. This tunnel is configured to handle **only** IPv6 traffic (`list addresses '2606:4700:110:81e6::xxxx/128'`), and the default IPv6 route (`::/0`) is bound exclusively to this interface.
    > All outbound local IPv6 traffic is dynamically wrapped in encrypted WireGuard UDP packets on port 500 and routed securely over the ISP's IPv4 network. This grants your home network full, blazing-fast dual-stack capabilities. Crucially, **your Egyptian ISP has zero visibility into what websites you are visiting or what queries you are making over IPv6**, as they only see encrypted packets traveling to Cloudflare!

3.  **Deploy IPv6 Route Helper Script:**
    Write the following helper script to `/etc/hotplug.d/iface/99-wg6-route` to ensure the route binds correctly on boot and restarts odhcpd to trigger IP leases:
    ```sh
    #!/bin/sh
    if [ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "wg0" ]; then
        sleep 3
        ip -6 route replace ::/0 dev wg0
        ip route flush cache
        /etc/init.d/odhcpd restart
    fi
    ```
    Make it executable:
    ```bash
    chmod +x /etc/hotplug.d/iface/99-wg6-route
    ```
    > [!IMPORTANT]
    > **Why the Custom `99-wg6-route` Hotplug Script is required:**
    > OpenWrt's default WireGuard interface handler has a known race condition: if the WAN connection goes down and re-establishes, the default IPv6 route pointing to `wg0` is often lost or fails to bind correctly. This custom script monitors interface events. The moment `wg0` comes up, it dynamically inserts the default IPv6 route (`::/0`) and restarts the DHCPv6/SLAAC server (`odhcpd`) to trigger fresh IPv6 address leases to all local clients. This ensures your IPv6 network never silently breaks!

4.  **Create Client Profile (`home.conf`):**
    Write the client configuration file to `/home/ztr/home.conf` for the remote mobile device (masked for privacy):
    ```ini
    [Interface]
    PrivateKey = CLIENT_PRIVATE_KEY
    Address = 10.9.0.2/24
    DNS = 10.9.0.1
    MTU = 1420

    [Peer]
    PublicKey = SERVER_PUBLIC_KEY
    PresharedKey = CLIENT_PRESHARED_KEY
    Endpoint = YOUR_DDNS_DOMAIN.duckdns.org:51820
    AllowedIPs = 0.0.0.0/0, ::/0
    PersistentKeepalive = 25
    ```
    > [!IMPORTANT]
    > **Why WireGuard MTU is set to 1420:**
    > Standard Ethernet packets have a Maximum Transmission Unit (MTU) of `1500` bytes. However, your PPPoE WAN connection adds encapsulation headers, reducing the usable MTU to `1492`. Additionally, WireGuard adds its own encryption and routing headers (at least 40–80 bytes).
    > If we send standard `1500` byte packets through the WireGuard tunnel, they will exceed the PPPoE MTU, causing the router to fragment the packets (break them into pieces) or drop them entirely (causing connection timeouts or slow page loads). Locking the WireGuard MTU to `1420` ensures all packets fit perfectly through the tunnel, maximizing transmission speeds and reducing router CPU load.

---

## 🔒 Phase 4: Airtight DNS & Interception Setup

We will configure AdGuard Home as the primary DNS with encrypted NextDNS upstreams, enforce loopback hijacking in the firewall, and restore L3 Dynamic IP Blocking.

1.  **Configure AdGuard Home Upstreams & Bootstrap:**
    Edit `/etc/adguardhome/adguardhome.yaml` and set up the upstreams and quoted bootstrap servers:
    ```yaml
    dns:
      upstream_dns:
        - quic://YOUR_NEXTDNS_ID.dns.nextdns.io
        - tls://8.8.8.8:853
        - '[/lan/]127.0.0.1:5353'
      bootstrap_dns:
        - "45.90.28.0"
        - "45.90.30.0"
        - "2a07:a8c0::"
        - "2a07:a8c1::"
        - "1.1.1.1"
        - "8.8.8.8"
      upstream_mode: parallel
      cache_enabled: true
      cache_size: 6294304
      cache_ttl_min: 3600
      cache_optimistic: true
      private_recv_dns_answers: true
      local_ptr_upstreams:
        - 127.0.0.1:5353
    ```
    > [!IMPORTANT]
    > **Advanced DNS Optimizations Explained:**
    > *   `cache_ttl_min: 3600` (1 Hour Minimum): Forces AdGuard to cache resolved DNS records for at least 1 hour, drastically reducing latency-bandwidth queries to NextDNS.
    > *   `cache_optimistic: true`: Tells AdGuard to immediately serve expired cache records to clients (0 ms latency), and asynchronously refresh the cache in the background.
    > *   **Quotes around IPv6 Bootstrap Addresses:** Colons (`:`) in YAML signify a key-value pair. Enclosing IPv6 addresses (e.g., `"2a07:a8c0::"`) in quotes is mandatory; otherwise, the YAML parser will throw a fatal error and crash AdGuard Home!

    > [!TIP]
    > **Why we assign a static Unique Local Address (ULA) prefix (`2a09:7373::1/64`):**
    > Unlike IPv4 where we use private addresses like `192.168.2.1`, IPv6 normally uses public addresses assigned by the provider. Because our IPv6 connection comes through a dynamic Cloudflare WARP tunnel, the WAN IPv6 prefix can change.
    > If we allowed local clients to use a dynamic IPv6 address for DNS, they would constantly lose connection to AdGuard Home when the tunnel toggles. By assigning a stable, private ULA IPv6 address (`2a09:7373::1`) to the LAN interface, clients always have a permanent, static IPv6 gateway to send their DNS queries to, guaranteeing uninterrupted resolving.

2.  **Add Interception Rules in `/etc/config/firewall`:**
    ```ini
    config redirect
            option name 'Intercept-DNS-UDP'
            option src 'lan'
            option src_dport '53'
            option proto 'udp'
            option target 'DNAT'

    config redirect
            option name 'Intercept-DNS-TCP'
            option src 'lan'
            option src_dport '53'
            option proto 'tcp'
            option target 'DNAT'

    config rule
            option name 'Block-DoT-853'
            option src 'lan'
            option dest '*'
            option dest_port '853'
            option proto 'tcp udp'
            option target 'REJECT'
    ```
    > [!IMPORTANT]
    > **Why DNS Interception (DNAT Port 53 Redirect) is airtight:**
    > Smart devices (like Google Chromecast, smart TVs, or game consoles) are often hardcoded to bypass the router's DNS and use public DNS servers (like `8.8.8.8` or `1.1.1.1`) to bypass ad-blocking or parental controls.
    > The `Intercept-DNS` firewall rules perform a **Destination NAT (DNAT)** redirect. They intercept any outbound packet targeting port 53 (DNS) on the internet and force-redirect it to the router's local AdGuard Home IP. The client device believes it is talking to `8.8.8.8`, but it is actually getting filtered answers from your local AdGuard Home.

    > [!IMPORTANT]
    > **Why DNS-over-TLS (Port 853) is rejected instead of redirected:**
    > Modern browsers and smartphones use encrypted DNS-over-TLS (DoT) on port 853. Since this traffic is encrypted, the router cannot inspect or modify it. If we redirected it to AdGuard Home, the client would detect a TLS certificate mismatch and refuse to load any pages.
    > By explicitly **rejecting** port 853 traffic at the firewall level, we tell the client device: *"Encrypted DoT is unavailable here."* The client's operating system will automatically and seamlessly fall back to standard plaintext DNS (port 53), which we then intercept and filter through AdGuard Home!

3.  **Upgrade `dnsmasq` to `dnsmasq-full` (Restore Layer 3 Blocks):**
    Install `dnsmasq-full` using OpenWrt's modern `apk` package manager to activate dynamic `nftset` capabilities:
    ```bash
    apk add dnsmasq-full
    /etc/init.d/dnsmasq restart
    ```
    > [!NOTE]
    > **Why `dnsmasq-full` is required for Layer 3 Blocking:**
    > The standard, lightweight `dnsmasq` package bundled with OpenWrt is compiled with `no-ipset` and `no-nftset` to save space. Because it lacks these compile-time features, the dynamic IP blocking rules in `/etc/config/dhcp` are silently ignored! Upgrading to `dnsmasq-full` compiles native `nftset` support, successfully completing your 3-layer VPN blocking loop.

4.  **Register VPN IPset in Firewall & DHCP:**
    *   In `/etc/config/firewall`:
        ```ini
        config ipset 'vpn_block'
                option name 'vpn_block'
                option match 'dest_ip'

        config rule
                option name 'Block-VPN-IPs'
                option src 'lan'
                option dest '*'
                option proto 'all'
                option target 'DROP'
                option ipset 'vpn_block'
        ```
    *   In `/etc/config/dhcp`, register the domains under `config dnsmasq`:
        ```ini
        list ipset '/nordvpn.com/vpn_block'
        list ipset '/expressvpn.com/vpn_block'
        list ipset '/surfshark.com/vpn_block'
        list ipset '/protonvpn.com/vpn_block'
        # ... Add remaining VPN provider domains here
        ```

---

## 🧱 Phase 5: Port 443 VPN Evasion Countermeasures

We will deploy firewall filters and traffic control rules to throttle and disrupt Stealth/WebSocket VPNs running on HTTPS port 443.

1.  **Block UDP 443 (Forces fallback to TCP):**
    Add the blocking rules to `/etc/config/firewall`:
    ```ini
    config rule
            option name 'Block-UDP-443-LAN'
            option src 'lan'
            option dest '*'
            option dest_port '443'
            option proto 'udp'
            option target 'REJECT'
            option family 'ipv4'

    config rule
            option name 'Block-UDP-443-LAN-v6'
            option src 'lan'
            option dest '*'
            option dest_port '443'
            option proto 'udp'
            option target 'REJECT'
            option family 'ipv6'
    ```
    > [!TIP]
    > **Why UDP 443 Blocking is safe and effective:**
    > UDP port 443 is used by QUIC (HTTP/3) and high-speed VPN protocols like WireGuard to bypass filters. By blocking UDP 443, we force these VPN clients to either fail or fall back to standard TCP-based HTTPS connections.
    > Normal web browsing is 100% unaffected because all modern browsers (Chrome, Safari, Firefox) are designed to instantly fall back to HTTP/2 over TCP on port 443 if UDP port 443 is blocked. Users will not notice any lag or disruption while browsing standard websites!

2.  **Write Traffic Shaping & Conntrack Rules to `/etc/firewall.user`:**
    Edit `/etc/firewall.user` to deploy custom `nftables` mangling (marks >50MB connection as `0x1`), clamps conntrack timeout to 5 minutes, and applies a `tc` HTB shaper on `br-lan`:
    ```sh
    #!/bin/sh
    # Wait for fw4 table to be ready
    sleep 2

    # Mark long-lived TCP 443 connections (>50MB = likely VPN tunnel)
    nft add chain inet fw4 vpn_throttle "{ type filter hook forward priority mangle - 1; policy accept; }" 2>/dev/null
    nft flush chain inet fw4 vpn_throttle 2>/dev/null
    nft add rule inet fw4 vpn_throttle iifname "br-lan" tcp dport 443 ct bytes > 52428800 meta mark set 0x1
    nft add rule inet fw4 vpn_throttle iifname "br-lan" tcp sport 443 ct bytes > 52428800 meta mark set 0x1

    # Short conntrack timeout for TCP 443 (5 min instead of 2+ hours)
    # Forces VPN tunnels to reconnect frequently, disrupting the experience
    nft add ct timeout inet fw4 vpn_short "{ protocol tcp; l3proto ip; policy = { established: 300, close_wait: 10, close: 10 }; }" 2>/dev/null

    # Throttle marked packets to 512kbps via tc on br-lan
    tc qdisc del dev br-lan root 2>/dev/null
    tc qdisc add dev br-lan root handle 1: htb default 10
    tc class add dev br-lan parent 1: classid 1:10 htb rate 1000mbit ceil 1000mbit
    tc class add dev br-lan parent 1: classid 1:20 htb rate 512kbit ceil 512kbit
    tc filter add dev br-lan parent 1: protocol ip handle 0x1 fw classid 1:20
    ```
    > [!IMPORTANT]
    > **How the 50 MB Conntrack Mark and 512 Kbps Shaper works:**
    > 1. **Web Browsing Pattern:** When you browse the web, your device opens hundreds of tiny, short-lived connections to load HTML, images, and scripts. These connections transfer very little data individually (typically <2-5 MB) and close quickly.
    > 2. **VPN Tunnel Pattern:** A VPN tunnel established over port 443 acts as a single, massive, long-lived connection that stays open indefinitely and routes all of your device's network traffic.
    > 3. **The Magic Counter (`ct bytes > 52428800`):** The router's firewall keeps track of every active connection's bandwidth. If a single connection on port 443 exceeds **50 Megabytes (52,428,800 bytes)** of data transfer, it is instantly classified as a VPN tunnel or an abusive download and marked with a tag (`0x1`).
    > 4. **The Shaper (`tc`):** The Traffic Control shaper catches any packet tagged `0x1` and restricts its maximum speed to a painful `512 Kbps` (dial-up speeds). This makes video streaming and web browsing over the VPN extremely frustrating and unusable, while unthrottled normal web browsing remains blazing fast!

    > [!IMPORTANT]
    > **Why Clamping Conntrack Established Timeout to 5 Minutes disrupts VPNs:**
    > By default, Linux keeps an established TCP connection in its memory table for **5 days (432,000 seconds)** even if no data is being sent. This allows a VPN tunnel to remain connected in the background forever.
    > By drastically reducing this timeout to **5 minutes (300 seconds)** for port 443 traffic, the router will instantly delete the connection from its memory if it goes idle for just a few minutes. This forces the client's stealth VPN tunnel to constantly tear down and renegotiate its connection, creating frequent interruptions, high latency, and battery drain on the VPN client!

3.  **Apply Firewall Rules:**
    ```bash
    /etc/init.d/firewall restart
    ```

---

## 🎛️ Phase 6: SQM Cake & Kernel Performance Tuning

We will configure SQM piece_of_cake and tune the TCP kernel parameters to eliminate bufferbloat and enable TCP Fast Open.

1.  **Configure SQM Cake:**
    Configure `/etc/config/sqm`:
    ```ini
    config queue 'eth1'
            option enabled '1'
            option interface 'pppoe-WAN'
            option download '54000'
            option upload '9200'
            option qdisc 'cake'
            option script 'piece_of_cake.qos'
            option linklayer 'ethernet'
            option use_mq '0'
            option debug_logging '0'
            option verbosity '5'
            option overhead '30'
            option qdisc_advanced '1'
            option squash_dscp '1'
            option squash_ingress '1'
            option ingress_ecn 'ECN'
            option egress_ecn 'ECN'
            option linklayer_advanced '1'
            option tcMTU '2047'
            option tcTSIZE '128'
            option tcMPU '0'
            option linklayer_adaptation_mechanism 'cake'
            option eqdisc_opts 'ack-filter'
    ```
    Restart SQM:
    ```bash
    /etc/init.d/sqm restart
    ```
    > [!TIP]
    > **Why SQM Cake and ECN eliminate Bufferbloat:**
    > Bufferbloat occurs when your ISP connection is saturated (e.g., someone downloading a massive file), causing the router's buffers to fill up. This delays other packets (like gaming keystrokes or voice calls), causing ping spikes of 500+ ms.
    > 1. **How SQM Cake helps:** Cake (Common Applications Kept Delicious) sits on your WAN interface and limits your speed to slightly below your actual line speed (e.g., 54 Mbps down, 9.2 Mbps up). By controlling the queue before your ISP's cheap modem does, Cake schedules packets fairly (Flow Queueing), ensuring that gaming and voice packets skip to the front of the line!
    > 2. **How ECN (Explicit Congestion Notification) works:** Instead of dropping packets when congestion occurs (which forces TCP to retransmit and lag), ECN marks packets with a special "congestion" flag. In synergy with the router's TCP BBR congestion control, this tells the sending device to smoothly slow down its transmission rate *before* any packets are dropped, maintaining a stable, low-latency connection.

    > [!IMPORTANT]
    > **Why Egress ACK Filtering is crucial for Asymmetric Connections:**
    > In many home networks, your upload speed (9.2 Mbps) is much slower than your download speed (54 Mbps). When downloading a large file, your PC must constantly upload "Acknowledgement" (ACK) packets to confirm it received the data.
    > If these ACK packets saturate your tiny 9.2 Mbps upload queue, they will get delayed. This forces the sending server to slow down its downloads, thinking your connection is congested. The `ack-filter` intelligently drops older, redundant ACK packets in the queue, keeping your upload pipe completely clear and maximizing your download speeds!

2.  **Optimize `/etc/sysctl.conf`:**
    Edit `/etc/sysctl.conf` to configure BBR congestion control, TCP Fast Open, and large UDP network buffers:
    ```ini
    net.netfilter.nf_conntrack_tcp_timeout_established = 600
    net.ipv6.conf.all.forwarding=1
    net.ipv6.conf.default.forwarding=1

    # Latency & Performance Tuning
    net.core.netdev_max_backlog = 5000
    net.ipv4.tcp_fastopen = 3
    net.ipv4.tcp_slow_start_after_idle = 0
    ```
    > [!TIP]
    > **Why we set `net.ipv4.tcp_fastopen = 3`:**
    > Enables TCP Fast Open (TFO) for both incoming and outgoing connections. TFO allows data to be sent during the initial TCP 3-way handshake, saving a full round-trip time (RTT) for repeated connections, making web requests feel much snappier.

    > [!TIP]
    > **Why we set `net.ipv4.tcp_slow_start_after_idle = 0`:**
    > Disables slow-start restart after a connection goes idle. Normally, TCP resets its congestion window size if a connection is idle, forcing it to slowly ramp up speed again. Disabling this ensures that active persistent connections instantly transmit at full speed when resuming activity.

3.  **Reload Sysctl Settings:**
    ```bash
    sysctl -p
    ```

---

## 🔋 Phase 7: Client Battery Optimizations

We will tune the Router Advertisements and neighbor cache timeouts to let wireless mobile devices enter deep sleep.

1.  **Configure SLAAC RAs in `/etc/config/dhcp`:**
    Edit the `lan` DHCP block:
    ```ini
    config dhcp 'lan'
            option interface 'lan'
            option start '200'
            option limit '51'
            option leasetime '12h'
            option dhcpv4 'server'
            list dhcp_option '6,192.168.2.1'
            option ra_management '0'
            option ra 'server'
            option dhcpv6 'disabled'
            option ra_default '2'
            option ra_maxinterval '600'
            option ra_mininterval '200'
            option ra_lifetime '1800'
            option ra_mtu '1280'
            option ra_unicast '1'
            list dns '2a09:7373::1'
            option ra_reachable '3600000'
            option ra_retransmit '2000'
    ```
    Restart DHCP service:
    ```bash
    /etc/init.d/dnsmasq restart
    ```
    > [!TIP]
    > **How Spaced-Out Router Advertisements (RAs) save Phone Battery:**
    > In IPv6, the router regularly sends Router Advertisement (RA) broadcast packets to tell devices that the network is still active. By default, these are sent every few seconds.
    > Every time your smartphone receives a broadcast packet, it must wake up its wireless radio from its low-power sleep state to process it, draining the battery in the background. By spacing the maximum RA interval to **10 minutes (`600` seconds)** and enabling **Unicast RAs** (where the router replies directly to a device rather than broadcasting to the entire network), your phone can remain in a deep sleep state for minutes at a time, extending battery life significantly.

    > [!IMPORTANT]
    > **Why locking the IPv6 RA MTU to 1280 is mandatory:**
    > Your IPv6 traffic routes through the Cloudflare WARP WireGuard tunnel, which has an MTU of `1420`. Normal internet packets have an MTU of `1500`.
    > If a client sends an IPv6 packet of 1500 bytes, the router cannot fit it through the 1420 WARP tunnel. In IPv6, routers are not allowed to fragment packets; they must drop the packet and send a message back to the client asking them to send smaller packets. If the client blocks these messages (due to firewall settings), the connection simply hangs (a "black hole" connection).
    > Locking the RA MTU to the absolute IPv6 minimum of `1280` forces all local clients to automatically send packets of 1280 bytes or less. This guarantees every IPv6 packet fits perfectly through the PPPoE WAN and the WARP tunnel with zero fragmentation or drops!

2.  **Configure 4-Hour Kernel NDP Cache:**
    Append the following relaxed base reachable times to `/etc/sysctl.conf`:
    ```ini
    # WiFi Battery Optimizations - Relax ARP/ND neighbor polling
    net.ipv4.neigh.default.base_reachable_time_ms = 14400000
    net.ipv4.neigh.br-lan.base_reachable_time_ms = 14400000
    net.ipv6.neigh.default.base_reachable_time_ms = 14400000
    net.ipv6.neigh.br-lan.base_reachable_time_ms = 14400000
    ```
    Apply kernel settings:
    ```bash
    sysctl -p
    ```
    > [!IMPORTANT]
    > **Why the 4-Hour neighbor base reachable time is a massive battery saver:**
    > By default, the Linux kernel only remembers which device owns which IP address (ARP for IPv4, NDP for IPv6) for about **30 seconds**. After 30 seconds, if the router wants to send a packet, it must broadcast a request asking: *"Who has this IP?"* This constant network polling wakes up your sleeping phone every 30 seconds.
    > By increasing the base reachable time to **4 hours (14,400,000 milliseconds)**, the router trusts its cached memory for 4 hours. It will not send any background polling packets to verify if your device is still there, allowing your phone to sleep peacefully without being woken up by constant router checks!

---

## 🔄 Phase 8: Dynamic DNS Setup & Cleanup

We will configure DuckDNS in UCI, configure the `dns_server` lookup bypass to avoid cache mismatch, and prune system files.

1.  **Configure DDNS in `/etc/config/ddns`:**
    Ensure `dns_server` is explicitly pointed to Cloudflare (`1.1.1.1`) to bypass local caches (domain name masked for privacy):
    ```ini
    config service 'myddns_ipv4'
            option enabled '1'
            option service_name 'duckdns.org'
            option ip_source 'interface'
            option lookup_host 'YOUR_DDNS_DOMAIN.duckdns.org'
            option use_ipv6 '0'
            option check_interval '10'
            option check_unit 'minutes'
            option force_interval '48'
            option force_unit 'hours'
            option domain 'YOUR_DDNS_DOMAIN'
            option username 'dummy'
            option password 'YOUR_DUCKDNS_TOKEN'
            option ip_interface 'pppoe-WAN'
            option use_syslog '2'
            option interface 'WAN'
            option dns_server '1.1.1.1'
    ```
    Restart service:
    ```bash
    /etc/init.d/ddns restart
    ```
    > [!TIP]
    > **Why the DDNS lookup bypass (`dns_server '1.1.1.1'`) is necessary:**
    > Your Dynamic DNS (DDNS) client on the router regularly checks if your home's public IP has changed by querying `YOUR_DDNS_DOMAIN.duckdns.org` and comparing it to your current WAN IP.
    > However, because we optimized AdGuard Home to cache DNS records for a minimum of **1 hour**, any query sent by the DDNS client through the local resolver would retrieve the **old cached IP** for up to an hour. The DDNS client would think the update failed, throw system warnings, and spam DuckDNS with duplicate update requests every 10 minutes.
    > Pointing the DDNS `dns_server` parameter directly to `1.1.1.1` forces it to bypass the local AdGuard cache and ask Cloudflare directly. Since Cloudflare respects DuckDNS's 60-second TTL, the router detects the new IP instantly, updates the LuCI GUI status immediately, and eliminates redundant update requests!

2.  **Prune Configuration Leftovers & Disable Unused package triggers:**
    ```bash
    # Remove backup and package leftovers
    rm -f /etc/config/dhcp.bak /etc/config/dhcp.apk-new /etc/adguardhome/adguardhome.yaml.bak /etc/firewall.user.bak
    
    # Disable unused proxy service at boot level
    /etc/init.d/sing-box disable
    ```

---

## 🔒 Phase 9: Advanced Security Hardening (CLI Setup)

To secure the router’s administration shell and network routing loops:

1.  **Configure SSH Key-Only authentication & Idle Auto-Timeouts:**
    *   First, add your computer's public key (e.g. `ssh-rsa AAAAB3N...`) to the router's authorized keys file `/etc/dropbear/authorized_keys`.
    *   Open `/etc/config/dropbear` in your terminal and modify the configuration to enforce key-only logins and terminate idle SSH connections after 5 minutes (`300` seconds):
        ```ini
        config dropbear
                option Port '22'
                option PasswordAuth '0'
                option RootPasswordAuth '0'
                option IdleTimeout '300'
        ```
    *   Restart the SSH service:
        ```bash
        /etc/init.d/dropbear restart
        ```
        > [!CAUTION]
        > Keep your current SSH session open, and test the key login in a new terminal window first to ensure you are not locked out!

2.  **Verify DNS Rebind Protection is Active:**
    Ensure dnsmasq is rejecting external resolutions that target private local subnets (blocking rebind attacks):
    *   Open `/etc/config/dhcp` and confirm the parameters under `config dnsmasq`:
        ```ini
        config dnsmasq
                option rebind_protection '1'
                option rebind_localhost '1'
        ```
    *   If changes are made, reload dnsmasq:
        ```bash
        /etc/init.d/dnsmasq restart
        ```

3.  **Strict WAN Management Isolation:**
    Confirm your firewall rejects all management connections (Port 22, 80, 443, 8080) originating from the WAN zone. By default, OpenWrt isolates WAN. Do not add any incoming WAN forward rules for ports other than the WireGuard server UDP port `51820`.

🌐 *Your gateway configuration is now fully completed, secure, optimized, and ready to serve LAN clients!*
