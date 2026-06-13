#!/bin/bash
# Shuka Hybrid Suite: Automated Deploy Script v2.5 (LTS)
# Edit these variables before running
ROUTER_IP="192.168.8.1"
ROUTER_PASS="YOUR_PASSWORD"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v sshpass &> /dev/null; then sudo apt-get update && sudo apt-get install -y sshpass; fi

sshpass -p "$ROUTER_PASS" ssh -o StrictHostKeyChecking=no root@$ROUTER_IP << 'EOR'
    PACKAGES="python3-light python3-urllib python3-openssl python3-codecs ca-bundle curl ca-certificates ip-full iptables kmod-tun"
    opkg update && opkg install $PACKAGES
    [ -L /lib/ld-linux-aarch64.so.1 ] || ln -s /lib/libc.so /lib/ld-linux-aarch64.so.1
    [ -c /dev/net/tun ] || (mkdir -p /dev/net && mknod /dev/net/tun c 10 200)
    mkdir -p /usr/bin /etc/init.d /etc/amneziawg/profiles /etc/sing-box /usr/lib/lua/luci/controller
EOR

for f in amneziawg-go awg-new sing-box; do sshpass -p "$ROUTER_PASS" ssh root@$ROUTER_IP "cat > /usr/bin/$f" < "$DIR/bin/$f"; done
for f in shuka_manager.py internet-protection.sh amneziawg-stop.sh start_shuka.sh amneziawg-dns.sh; do sshpass -p "$ROUTER_PASS" ssh root@$ROUTER_IP "cat > /usr/bin/$f" < "$DIR/scripts/$f"; done
sshpass -p "$ROUTER_PASS" ssh root@$ROUTER_IP "cat > /etc/init.d/internet-protection" < "$DIR/init/internet-protection.init"
sshpass -p "$ROUTER_PASS" ssh root@$ROUTER_IP "cat > /etc/init.d/shuka-boot" < "$DIR/init/shuka-boot.init"
sshpass -p "$ROUTER_PASS" ssh root@$ROUTER_IP "cat > /usr/lib/lua/luci/controller/shuka_hybrid.lua" < "$DIR/luci/shuka_hybrid.lua"
sshpass -p "$ROUTER_PASS" ssh root@$ROUTER_IP "cat > /etc/sing-box/config.json.template" < "$DIR/config.json.template"

sshpass -p "$ROUTER_PASS" ssh root@$ROUTER_IP << 'EOR'
    chmod +x /usr/bin/* && chmod +x /etc/init.d/*
    /etc/init.d/internet-protection enable && /etc/init.d/internet-protection start
    /etc/init.d/shuka-boot enable
    rm -f /tmp/luci-indexcache && /etc/init.d/uhttpd restart
EOR
echo "Done!"
