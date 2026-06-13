#!/bin/sh
IFACE="awg0"
logger -t awg-stop "Stopping AmneziaWG and restoring network..."

# 1. Удаление маршрутов (включая маршрут к Endpoint)
ip route del 0.0.0.0/1 dev $IFACE 2>/dev/null
ip route del 128.0.0.0/1 dev $IFACE 2>/dev/null
# Удаляем маршрут к серверу, чтобы вернуть его на дефолтный шлюз
ENDPOINT_IP=$(awg show $IFACE endpoint 2>/dev/null | awk '{print $2}' | cut -d: -f1)
if [ -n "$ENDPOINT_IP" ]; then
    ip route del $ENDPOINT_IP 2>/dev/null
fi

# 2. Остановка процессов и интерфейса
killall amneziawg-go 2>/dev/null
ip link delete $IFACE 2>/dev/null

# 3. Очистка Firewall и восстановление IPv6
iptables -t nat -D POSTROUTING -o $IFACE -j MASQUERADE 2>/dev/null
iptables -D FORWARD -i br-lan -o $IFACE -j ACCEPT 2>/dev/null
iptables -D FORWARD -i $IFACE -o br-lan -j ACCEPT 2>/dev/null

ip6tables -D FORWARD -j REJECT 2>/dev/null
sysctl -w net.ipv6.conf.all.disable_ipv6=0
sysctl -w net.ipv6.conf.default.disable_ipv6=0

# 4. Сброс DNS (выключаем Safe DNS)
/usr/bin/amneziawg-dns.sh off

ip route flush cache
logger -t awg-stop "SUCCESS: Network restored to original state"
