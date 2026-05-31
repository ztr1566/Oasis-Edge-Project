# 🖱️ Project OasisEdge: GUI-Based Setup & Optimization Guide

This document provides a step-by-step setup guide to reproduce **Project OasisEdge**—your fully optimized, dual-stack, privacy-first OpenWrt gateway—entirely through the **LuCI Web interface** and the **AdGuard Home Web Dashboard**. 

If you prefer to configure, inspect, and maintain your router visually in your web browser instead of using SSH and command-line interfaces (CLI), this guide outlines the exact menu paths, button clicks, and settings fields needed. It features a proud focus on operating a secure, private dual-stack IPv6 network in **Egypt** (where ISPs only provide legacy IPv4-only connections).

---

## 🇪🇬 Bypassing Single-Stack IPv4 in Egypt via GUI
Because mainstream Egyptian ISPs do not support native IPv6, **Project OasisEdge** uses an encrypted tunnel to transport IPv6 traffic over the native IPv4 network. 
* By configuring a Cloudflare WARP WireGuard interface (`wg0`) in LuCI and routing all IPv6 traffic (`::/0`) into it, we bring full dual-stack capabilities to your home.
* Since all IPv6 data is encrypted at the router before transit, **your local ISP cannot monitor, log, or restrict your IPv6 activity**. This guide details how to build this secure gateway completely using the web GUI.

---

## 🧭 Master LuCI Navigation Matrix

Here is where all configurations are located in the OpenWrt Web GUI:

```
[ LuCI Dashboard ]
  ├── System
  │     ├── Administration ──────> Root Password setup & SSH Keys
  │     └── Software ────────────> Install packages (SQM, WireGuard, DDNS, dnsmasq-full)
  ├── Network
  │     ├── Interfaces ──────────> LAN, WAN, Modem, wg0 (WARP), wg1 (Server)
  │     ├── Firewall ────────────> Port Forwards, Traffic Rules, Custom Rules, IPsets
  │     ├── SQM QoS ─────────────> SQM Cake bufferbloat management
  │     └── DHCP and DNS ────────> DNS Rebind Protection & Dnsmasq settings
  └── Services
        └── Dynamic DNS ─────────> DuckDNS configuration and lookup bypass
```

---

## 🏁 Phase 1: Initial LuCI Access & Password Setup

```
[ Connect LAN Cable ] ──> [ Browser: 192.168.2.1 ] ──> [ System -> Administration ] ──> [ Save Root Password ]
```

1.  **Initial Boot & Connection:**
    *   Connect your computer's Ethernet port to the Orange Pi Zero 3's Ethernet port.
    *   Open your web browser and navigate to: `http://192.168.2.1` (or `http://192.168.1.1` depending on initial image state).
    *   Click **Login** (leave password blank if logging in for the first time).
2.  **Set Root Password:**
    *   Navigate to **System** ➔ **Administration** in the top menu.
    *   Under the **Router Password** section:
        *   **Password:** Enter your secure password.
        *   **Confirmation:** Re-enter your secure password.
    *   Scroll down and click **Save & Apply**.

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
    *   **VLAN ID:** Ensure **Enable VLAN ID** is **Unchecked** (Disabled). Do **not** enable VLAN tagging (such as VLAN 50 or 51), as doing so is not needed and will prevent the PPPoE connection from handshaking successfully.
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

We will configure the LAN static IP, PPPoE WAN connection, the dynamic Packet Steering trigger, and the secondary Modem access bridge.

### 1. Configure the LAN Interface
*   Navigate to **Network** ➔ **Interfaces**.
*   Click **Edit** next to the **lan** interface.
*   **General Setup** tab:
    *   **IPv4 Address:** `192.168.2.1`
    *   **IPv4 Netmask:** `255.255.255.0`
    *   **IPv6 assignment length:** Set to `Disabled` (or delete any default ISP prefixes as we will use a dedicated local IPv6 ULA gateway).
*   **Advanced Settings** tab:
    *   **Use built-in IPv6-management:** Uncheck (Disabled).
    *   **Force Link:** Check.
*   **Static IPv6 LAN Gateway (ULA Setup):**
    *   Scroll to the bottom under **IPv6 Addresses** (or click **Add**).
    *   Add a stable static local IPv6 ULA address: `2a09:7373::1/64`
*   Click **Save** (do not click *Save & Apply* yet, we will apply all interfaces together).

### 2. Configure the WAN PPPoE Interface
*   Navigate to **Network** ➔ **Interfaces**.
*   Click **Edit** next to your **WAN** interface (or click **Add New Interface**, name it `WAN`, and select protocol `PPPoE`).
*   **General Setup** tab:
    *   **Protocol:** Select `PPPoE` and click **Switch Protocol** if changing it.
    *   **PAP/CHAP Username:** Enter `YOUR_PPPOE_USERNAME`
    *   **PAP/CHAP Password:** Enter `YOUR_PPPOE_PASSWORD`
*   **Advanced Settings** tab:
    *   **Use DNS servers advertised by peer:** **Uncheck** (Disabled). This prevents the ISP from overriding your DNS.
    *   **Use custom DNS servers:** Add two lines:
        *   `127.0.0.1` (Points local queries to AdGuard Home)
        *   `1.1.1.1` (Backup fallback)
*   Click **Save**.

### 3. Create the Modem Access Interface
*   Navigate to **Network** ➔ **Interfaces**.
*   Click **Add New Interface** at the bottom.
    *   **Name:** `modem`
    *   **Protocol:** Select `Static address`
    *   **Device:** Select `br-lan` (This binds it directly to your local Ethernet bridge).
    *   Click **Create Interface**.
*   In the configuration modal:
    *   **IPv4 Address:** `192.168.1.50`
    *   **IPv4 Netmask:** `255.255.255.0`
    *   Click **Save**.

> [!NOTE]
> **Why we configure the static 'modem' interface in the GUI:**
> Your upstream physical modem originally operated as the primary router at `192.168.1.1`. To prevent double-NAT lag, we bridged the modem and moved our local network to `192.168.2.x`. Because your PC is now on the `192.168.2.x` subnet, it cannot communicate with the `192.168.1.x` network.
> By creating the virtual static interface `192.168.1.50` on the local bridge (`br-lan`), your OpenWrt router gains a secondary IP address in the modem's subnet. Now, when you enter `192.168.1.1` in your browser, the router routes the packets directly to the bridged modem, allowing you to check DSL/fiber sync parameters without moving any cables!

### 4. Enable Global Packet Steering
*   Navigate to **Network** ➔ **Interfaces** ➔ **Global Options** (top sub-tab).
*   **Packet Steering:** Check **Enabled** (this activates Option `2` under-the-hood).
*   Click **Save & Apply** at the bottom right.

---

## 🛡️ Phase 3: Secure VPN Tunnels Configuration

We will configure the Cloudflare WARP client tunnel for IPv6 outbounds and the WireGuard Server for remote mobile access.

### 1. Install WireGuard GUI Packages
*   Navigate to **System** ➔ **Software**.
*   Click **Update Lists** to update the package index.
*   In the **Filter** box, type `luci-app-wireguard`.
*   Click **Install** next to `luci-app-wireguard` (this automatically downloads `wireguard-tools` and dependencies).
*   Perform a quick system reboot under **System** ➔ **Reboot** to ensure LuCI loads the interface protocols.

### 2. Configure Cloudflare WARP IPv6 Client Tunnel (`wg0`)
*   Navigate to **Network** ➔ **Interfaces**.
*   Click **Add New Interface**:
    *   **Name:** `wg0`
    *   **Protocol:** `WireGuard VPN`
    *   Click **Create Interface**.
*   **General Setup** tab:
    *   **Private Key:** Paste `YOUR_WARP_PRIVATE_KEY` (generated locally or via wgcf).
    *   **IP Addresses:** Paste your WARP client IPv6 address: `2606:4700:110:81e6::xxxx/128`
*   **Peers** tab ➔ Click **Add Peer**:
    *   **Description:** `Cloudflare_WARP`
    *   **Public Key:** `bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=`
    *   **Allowed IPs:** Add `::/0` (Routes all local IPv6 traffic through the tunnel).
    *   **Endpoint Host:** `188.114.97.170`
    *   **Endpoint Port:** `500`
    *   **Route Allowed IPs:** **Check** (Enabled).
    *   **Persistent Keepalive:** `25`
*   Click **Save**.

> [!TIP]
> **Why Cloudflare WARP is used for IPv6 (Dual-Stack Isolation in Egypt):**
> Your physical ISP connection in Egypt is native IPv4-only and does not support modern IPv6. To achieve a modern dual-stack network, we create a secure WireGuard tunnel (`wg0`) to Cloudflare WARP. This tunnel is configured to handle **only** IPv6 traffic (`list addresses '2606:4700:110:81e6::xxxx/128'`). The default IPv6 route (`::/0`) is directed exclusively into this tunnel. 
> This design achieves two massive benefits:
> 1. You get full IPv6 internet capabilities.
> 2. Your local ISP cannot track, inspect, or log any of your IPv6 browsing activity because it is wrapped in standard encrypted WireGuard UDP packets on port 500 going to Cloudflare.

### 3. Configure the WireGuard Server Tunnel (`wg1`)
*   Navigate to **Network** ➔ **Interfaces**.
*   Click **Add New Interface**:
    *   **Name:** `wg1`
    *   **Protocol:** `WireGuard VPN`
    *   Click **Create Interface**.
*   **General Setup** tab:
    *   **Private Key:** Paste `YOUR_SERVER_PRIVATE_KEY`
    *   **Listen Port:** `51820`
    *   **IP Addresses:** Add Server local subnet IP: `10.9.0.1/24`
*   **Peers** tab ➔ Click **Add Peer**:
    *   **Description:** `Mobile_Client`
    *   **Public Key:** `CLIENT_PUBLIC_KEY`
    *   **Preshared Key:** `CLIENT_PRESHARED_KEY`
    *   **Allowed IPs:** Add `10.9.0.2/32` (Forces routing only for this remote host IP).
    *   **Route Allowed IPs:** **Check** (Enabled).
*   **Firewall Settings** tab:
    *   **Create / Assign firewall-zone:** Select **lan** (This securely joins remote WireGuard clients to your local home network).
*   Click **Save** and then click **Save & Apply**.

### 4. Create the WireGuard WAN Access Firewall Rule
To allow remote clients to handshake with your server:
*   Navigate to **Network** ➔ **Firewall** ➔ **Traffic Rules**.
*   Scroll down and click **Add**.
    *   **Name:** `Allow-WireGuard-Server`
    *   **Protocol:** `UDP`
    *   **Source zone:** `wan`
    *   **Destination zone:** `Device (input)`
    *   **Destination port:** `51820`
    *   **Action:** `accept`
*   Click **Save** and then **Save & Apply**.

---

## 🔒 Phase 4: Airtight DNS & Interception Setup

We will configure NextDNS upstreams in the AdGuard Home Web Panel and enforce the local port redirection rules in LuCI.

### 1. Configure AdGuard Home Web Panel
*   Open your browser and go to the AdGuard Home Setup portal: `http://192.168.2.1:3000` (or `http://192.168.2.1:8080` once configured).
*   Navigate to **Settings** ➔ **DNS Settings**.
*   **Upstream DNS Servers:**
    *   Enter your NextDNS (DNS-over-QUIC) server and secondary TLS fallback:
        ```text
        quic://YOUR_NEXTDNS_ID.dns.nextdns.io
        tls://8.8.8.8:853
        [/lan/]127.0.0.1:5353
        ```
    *   **Upstream Mode:** Select **Parallel** (Queries all servers simultaneously, choosing the fastest response).
*   **Bootstrap DNS Servers:**
    Enter the following IP addresses. *Colons inside IP addresses are parsed as key-value pairs in YAML config files, but in the GUI text field, you simply enter them line-by-line as plaintext (the GUI automatically wraps quotes in the background):*
    ```text
    45.90.28.0
    45.90.30.0
    2a07:a8c0::
    2a07:a8c1::
    1.1.1.1
    8.8.8.8
    ```
*   **DNS Cache Configuration:**
    *   **Cache Size:** `6294304` (6 MB)
    *   **Minimum TTL:** `3600` (1 Hour - locks results in cache to reduce external NextDNS queries).
    *   **Optimistic Caching:** **Check** (Enabled - instantly serves expired entries while refreshing in the background).
*   Click **Apply**.

### 2. Configure DNS Interception in LuCI (DNAT Redirection)
To force all LAN devices to use AdGuard Home DNS and block DoT bypasses:
*   Navigate to **Network** ➔ **Firewall** ➔ **Port Forwards** tab.
*   Click **Add**:
    *   **Name:** `Intercept-DNS-UDP`
    *   **Protocol:** `UDP`
    *   **Source zone:** `lan`
    *   **External port:** `53`
    *   **Destination zone:** `Device (input)`
    *   **Internal IP address:** `192.168.2.1` (or local loopback)
    *   **Internal port:** `53`
    *   Click **Save**.
*   Click **Add** again (for TCP):
    *   **Name:** `Intercept-DNS-TCP`
    *   **Protocol:** `TCP`
    *   **Source zone:** `lan`
    *   **External port:** `53`
    *   **Destination zone:** `Device (input)`
    *   **Internal IP address:** `192.168.2.1`
    *   **Internal port:** `53`
    *   Click **Save**.

### 3. Block Encrypted DNS-over-TLS (Port 853)
*   Navigate to **Network** ➔ **Firewall** ➔ **Traffic Rules** tab.
*   Click **Add**:
    *   **Name:** `Block-DoT-853`
    *   **Protocol:** `TCP` & `UDP` (or select `TCP` and add a secondary rule for `UDP`)
    *   **Source zone:** `lan`
    *   **Destination zone:** `Any zone (forward)`
    *   **Destination port:** `853`
    *   **Action:** `reject`
    *   Click **Save** and then **Save & Apply**.

> [!IMPORTANT]
> **Why DoT is rejected rather than redirected:**
> DNS-over-TLS is encrypted. If the router attempts to intercept/redirect port 853 traffic to AdGuard Home, the client will immediately detect a TLS certificate signature mismatch and terminate all network connections. Explicitly **rejecting** the connection signals the client that DoT is unavailable, forcing the device to automatically fall back to standard plaintext DNS on port 53, which is then cleanly intercepted by our redirect rules!

### 4. Upgrade `dnsmasq` in the Software GUI
*   Navigate to **System** ➔ **Software**.
*   Click **Update Lists**.
*   Search for `dnsmasq` under **Installed** and click **Uninstall** (or perform this swap in your terminal to ensure uninterrupted DHCP leasing).
*   Immediately search for `dnsmasq-full` in **Available** and click **Install**.
*   *Note: This enables dynamic NFTsets, which matches resolved domain IPs and routes them to firewall blocking lists.*

---

## 🧱 Phase 5: Port 443 VPN Evasion Traffic Rules

We will block UDP Port 443 (disrupting WireGuard/QUIC VPNs) and deploy the traffic shaping controls.

### 1. Configure the UDP 443 Block Rules in LuCI
*   Navigate to **Network** ➔ **Firewall** ➔ **Traffic Rules**.
*   Click **Add**:
    *   **Name:** `Block-UDP-443-LAN`
    *   **Protocol:** `UDP`
    *   **Source zone:** `lan`
    *   **Destination zone:** `Any zone (forward)`
    *   **Destination port:** `443`
    *   **Action:** `reject`
*   Click **Save**.
*   Click **Edit** next to the rule you just created:
    *   Under the **Advanced Settings** tab, ensure **Restrict to Address Family** is set to `IPv4 only`.
    *   Click **Save**.
*   Click **Add** again (for IPv6):
    *   **Name:** `Block-UDP-443-LAN-v6`
    *   **Protocol:** `UDP`
    *   **Source zone:** `lan`
    *   **Destination zone:** `Any zone (forward)`
    *   **Destination port:** `443`
    *   **Action:** `reject`
    *   Click **Save**, click **Edit** ➔ **Advanced Settings** ➔ **Restrict to Address Family** ➔ Select `IPv6 only`.
    *   Click **Save** and then **Save & Apply**.

### 2. Deploy the 50 MB Throttling & TCP Clamping Rules
*   Navigate to **Network** ➔ **Firewall** ➔ **Custom Rules** (or write these directly to the `/etc/firewall.user` script).
*   Paste the following commands to dynamically identify heavy port 443 tunnels and limit their speed to 512 Kbps:
    ```sh
    # Wait for firewalls to boot
    sleep 2

    # Mark port 443 traffic exceeding 50 MB
    nft add chain inet fw4 vpn_throttle { type filter hook forward priority mangle - 1; policy accept; } 2>/dev/null
    nft flush chain inet fw4 vpn_throttle 2>/dev/null
    nft add rule inet fw4 vpn_throttle iifname "br-lan" tcp dport 443 ct bytes > 52428800 meta mark set 0x1
    nft add rule inet fw4 vpn_throttle iifname "br-lan" tcp sport 443 ct bytes > 52428800 meta mark set 0x1

    # Clamp inactive port 443 connections to 5 minutes
    nft add ct timeout inet fw4 vpn_short { protocol tcp; l3proto ip; policy = { established: 300, close_wait: 10, close: 10 }; } 2>/dev/null

    # Enforce Traffic Control (tc) on the bridge
    tc qdisc del dev br-lan root 2>/dev/null
    tc qdisc add dev br-lan root handle 1: htb default 10
    tc class add dev br-lan parent 1: classid 1:10 htb rate 1000mbit ceil 1000mbit
    tc class add dev br-lan parent 1: classid 1:20 htb rate 512kbit ceil 512kbit
    tc filter add dev br-lan parent 1: protocol ip handle 0x1 fw classid 1:20
    ```
*   Click **Save & Apply**.

---

## 🎛️ Phase 6: SQM Cake Setup

We will configure the Hierarchical Token Bucket and Cake queuing algorithm to eliminate latency bufferbloat.

### 1. Install SQM GUI Package
*   Navigate to **System** ➔ **Software**.
*   Search for `luci-app-sqm` and click **Install**.
*   Refresh your browser tab or log back in to load the SQM menu.

### 2. Configure SQM Interfaces
*   Navigate to **Network** ➔ **SQM QoS**.
*   Under the **Basic Settings** tab:
    *   **Enable:** **Check** (Enabled).
    *   **Interface name:** Select your active WAN link: `pppoe-WAN`.
    *   **Download Speed (kbit/s):** `54000` (Leaves a safety margin under your 60 Mbps link).
    *   **Upload Speed (kbit/s):** `9200` (Leaves a safety margin under your 10 Mbps upload).
*   Under the **Queue Discipline** tab:
    *   **Queuing discipline:** Select `cake`.
    *   **Queue setup script:** Select `piece_of_cake.qos`.
*   Under the **Link Layer Adaptation** tab:
    *   **Link layer:** Select `Ethernet`.
    *   **Overhead:** `30`
*   Click **Save & Apply**.

---

## 🔋 Phase 7: SLAAC RA & Battery Optimizations

We will space out dynamic Router Advertisements to allow WiFi clients to sleep and configure MTU constraints.

1.  **Configure LAN IPv6 parameters:**
    *   Navigate to **Network** ➔ **Interfaces**.
    *   Click **Edit** next to the **lan** interface.
    *   Scroll down to the **DHCP Server** section and click the **IPv6 Settings** sub-tab:
        *   **Router Advertisement-Service:** `server mode`
        *   **DHCPv6-Service:** `disabled`
        *   **NDP-Proxy:** `disabled`
        *   **Local IPv6 DNS server:** Enter `2a09:7373::1`
2.  **Configure Spaced-Out RA Timers:**
    *   Click the **IPv6 RA Settings** sub-tab:
        *   **Default router:** Select `forced` (Forces clients to route IPv6 through OpenWrt).
        *   **Maximum RA interval:** `600` (10 minutes - prevents periodic broadcast wakeups).
        *   **RA MTU:** `1280` (IPv6 minimum MTU - guarantees packets fit within PPPoE and WireGuard interfaces without fragmenting).
        *   **Enable unicast responses:** **Check** (Enabled - the router replies directly to device queries rather than broadcasting to the entire WiFi subnet).
3.  **Click Save & Apply.**

---

## 🔄 Phase 8: Dynamic DNS Setup

We will configure DuckDNS IP syncs and set the lookup server parameter to bypass local AdGuard Home caches.

### 1. Install DDNS GUI Package
*   Navigate to **System** ➔ **Software**.
*   Search for `luci-app-ddns` and click **Install**.
*   Re-login to reload the menu hierarchy.

### 2. Configure DuckDNS Sync Settings
*   Navigate to **Services** ➔ **Dynamic DNS**.
*   Click **Add** (or **Edit** next to an existing IPv4 profile):
    *   **Name:** `myddns_ipv4`
    *   **Service provider:** `duckdns.org`
*   In the configuration modal:
    *   **Enabled:** **Check** (Enabled).
    *   **Lookup Hostname:** Enter `YOUR_DDNS_DOMAIN.duckdns.org`
    *   **Domain:** Enter `YOUR_DDNS_DOMAIN`
    *   **Password/Token:** Enter `YOUR_DUCKDNS_TOKEN`
    *   **IP address source:** `Interface`
    *   **Interface:** `pppoe-WAN`
    *   **Check Interval:** `10` minutes.
*   **Bypass Local Cache (Direct Resolving):**
    *   Click the **Advanced Settings** tab at the top.
    *   **DNS Server:** Enter `1.1.1.1` (Forces the update script to query Cloudflare directly instead of querying your local AdGuard Home resolver, avoiding cached-IP mismatches and sync errors).
*   Click **Save** and then **Save & Apply**.
*   Click the **Start** button next to your DDNS service profile. The GUI status will change to a green checkmark indicating successful updates!

---

## 🔒 Phase 9: Advanced Security Hardening (GUI Setup)

To secure the router's operating system interface and network zones visually:

### 1. Configure SSH Key-Only authentication & Disable Passwords
*   Navigate to **System** ➔ **Administration**.
*   Click the **SSH Keys** tab at the top:
    *   Paste your local machine's public SSH key into the text box.
    *   Click **Add Key**.
*   Now click the **SSH Access** tab (first tab):
    *   For the Dropbear Instance listening on port 22:
        *   **Password authentication:** **Uncheck** (Disabled).
        *   **Allow root logins with password:** **Uncheck** (Disabled).
        *   **Gateway ports:** Unchecked.
*   Scroll to the bottom under **Dropbear Settings**:
    *   **Connection Keep-Alive / Idle Timeout:** Set to `300` (Enforces connection auto-termination after 5 minutes of inactivity).
*   Click **Save & Apply**.
    > [!WARNING]
    > Do not close your current terminal or SSH connection yet! Open a new terminal and verify that you can log in with your SSH key successfully and that the password prompt is rejected.

### 2. Verify DNS Rebind Protection
*   Navigate to **Network** ➔ **DHCP and DNS**.
*   Under the **General Settings** tab:
    *   **Rebind protection:** **Check** (Enabled - rejects upstream DNS answers that resolve to local private IP subnets).
    *   **Allow localhost rebinding:** **Check** (Enabled - allows loopback address mappings like `127.0.0.1` locally).
*   Click **Save & Apply**.

### 3. Audit WAN Security Policies
*   Navigate to **Network** ➔ **Firewall**.
*   Under the **Zones** tab, scroll to the `wan` row:
    *   Verify that **Input** is set to `reject` or `drop`.
    *   Verify that **Forward** is set to `reject` or `drop`.
    *   *Note: This isolates all WAN interface incoming queries, ensuring your router's admin panels are only reachable when connected on local LAN or using the WireGuard `wg1` handshake.*

---

🌐 *All setups, tunnels, security policies, and performance optimizations are now fully configured and visual in your **Project OasisEdge** web interface!*
