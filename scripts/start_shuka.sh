#!/bin/sh
IFACE="awg0"
CONF="/etc/amneziawg/awg0.conf"
AWG_TOOL="/usr/bin/awg"

echo "[$(date)] --- STARTING KERNEL SHUKA VPN (v4.9.0) ---"

# 1. Принудительная очистка
killall amneziawg-go 2>/dev/null
ip link delete $IFACE 2>/dev/null
sleep 1

# 2. Создание нативного интерфейса
ip link add dev $IFACE type amneziawg

# 3. Подготовка и загрузка конфигурации
# Очищаем конфиг от Address, DNS и пустых I* параметров для системной утилиты
grep -vE "^Address|^DNS|^I[1-5] += *$" "$CONF" | grep -vE "^I[1-5] = *$" > /tmp/awg_kernel.conf

$AWG_TOOL setconf $IFACE /tmp/awg_kernel.conf

# 4. Настройка сети
IP_ADDR=$(grep Address $CONF | awk '{print $3}' | cut -d/ -f1)
ip addr add ${IP_ADDR:-10.8.1.27}/32 dev $IFACE
ip link set mtu 1280 dev $IFACE
ip link set $IFACE up

# 5. Маршрутизация
GW=$(ip route show default | awk '/default/ {print $3}' | head -n1)
DEV=$(ip route show default | awk '/default/ {print $5}' | head -n1)
ENDPOINT=$(grep Endpoint $CONF | awk '{print $3}' | cut -d: -f1)

if [ -n "$GW" ] && [ -n "$ENDPOINT" ]; then
    echo "Шлюз: $GW через $DEV, Сервер: $ENDPOINT"
    ip route add $ENDPOINT via $GW dev $DEV 2>/dev/null
fi

ip route add 0.0.0.0/1 dev $IFACE
ip route add 128.0.0.0/1 dev $IFACE

# 6. Firewall
iptables -I FORWARD -i br-lan -o $IFACE -j ACCEPT
iptables -I FORWARD -i $IFACE -o br-lan -j ACCEPT
iptables -t nat -I POSTROUTING -o $IFACE -j MASQUERADE

echo "--- СТАТУС ЯДРА ---"
$AWG_TOOL show $IFACE
