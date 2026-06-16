# Shuka Hybrid Suite for OpenWrt

Ultimate VPN solution for GL.iNet and other OpenWrt routers (aarch64). 
Features hybrid engine support: Native AmneziaWG Kernel Mode and Sing-box for subscriptions.

## Key Features
- **Native AmneziaWG 2.0 Support**: Works directly with the router's kernel (starting from v4.9.0) for maximum speed and efficiency.
- **Sing-box Integration**: Supports VLESS, Shadowsocks, and Trojan protocols with Reality/TLS.
- **Smart DNS**: Integrated DoH (DNS over HTTPS) and bypass rules for local services.
- **Internet Protection**: Aggressive watchdog that restores direct connectivity if VPN fails.
- **Full LuCI Web Interface**: Manage subscriptions, import Amnezia profiles, and monitor traffic in real-time.
- **Auto-start**: Restores last active connection after reboot or when a mobile modem connects.

## Installation

### Method 1: Using IPK (Recommended)
1. Upload the `.ipk` file to your router.
2. Run:
   ```bash
   opkg update
   opkg install amneziawg-shuka-suite_4.0.4_aarch64_cortex-a53.ipk
   ```

## Requirements
- OpenWrt 21.02+ (or GL.iNet v4.x)
- aarch64 architecture (Flint 2, Beryl AX, etc.)
- Python 3 for subscription manager

## License
MIT
