#!/bin/sh

# Internet Protection Watchdog v2.0 (Aggressive Rescue)
# Description: Monitors connectivity via multiple hosts and performs deep cleanup on failure.

LOG_FILE="/root/internet_protection.log"
FAIL_COUNT=0
MAX_FAILS=5
STATE="OK"

# Список хостов для проверки (пингуем по IP, чтобы не зависеть от DNS)
CHECK_HOSTS="8.8.8.8 1.1.1.1 9.9.9.9"

log_event() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    logger -t internet-protection "$1"
}

aggressive_rescue() {
    log_event "RESCUE_START: Начинаю агрессивную очистку маршрутов и правил..."
    
    # 1. Останавливаем процессы
    killall amneziawg-go 2>/dev/null
    /etc/init.d/amneziawg stop 2>/dev/null
    
    # 2. Удаляем интерфейс
    ip link delete awg0 2>/dev/null
    
    # 3. Принудительная очистка маршрутов (всех возможных кусков)
    while ip route del 0.0.0.0/1 2>/dev/null; do :; done
    while ip route del 128.0.0.0/1 2>/dev/null; do :; done
    
    # Удаляем маршруты к VPN эндпоинтам
    ip route show | grep via | while read -r line; do
        # Если маршрут специфичный (не локалка и не дефолт), удаляем его
        dest=$(echo "$line" | awk '{print $1}')
        if [ "$dest" != "default" ] && [ "$dest" != "192.168.8.0/24" ] && [ "$dest" != "192.168.1.0/24" ]; then
            ip route del $dest 2>/dev/null
        fi
    done

    # 4. Сброс Firewall (очистка цепочек, которые могли быть созданы скриптами)
    # Мы не сбрасываем всё, чтобы не убить NAT роутера, но удаляем правила для awg0
    iptables -t nat -D POSTROUTING -o awg0 -j MASQUERADE 2>/dev/null
    iptables -D FORWARD -i br-lan -o awg0 -j ACCEPT 2>/dev/null
    iptables -D FORWARD -i awg0 -o br-lan -j ACCEPT 2>/dev/null
    
    # 5. Восстановление DNS
    if command -v uci >/dev/null; then
        uci set network.wan.peerdns='1'
        uci del network.wan.dns 2>/dev/null
        uci commit network
        /etc/init.d/dnsmasq restart 2>/dev/null
    fi
    
    # 6. Сброс кэша ядра
    ip route flush cache
    
        /usr/bin/amneziawg-dns.sh off
    log_event "RESCUE_COMPLETE: Система возвращена к прямому соединению."
}

log_event "WATCHDOG_START: Усиленная защита интернета v2.0 запущена."

while true; do
    SUCCESS=0
    for host in $CHECK_HOSTS; do
        if ping -c 1 -W 2 "$host" > /dev/null 2>&1; then
            SUCCESS=1
            break
        fi
    done

    if [ "$SUCCESS" -eq 1 ]; then
        if [ "$STATE" = "DOWN" ]; then
            log_event "INTERNET_RESTORED: Связь восстановлена."
            STATE="OK"
        fi
        FAIL_COUNT=0
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        logger -t internet-protection "Ping failed ($FAIL_COUNT/$MAX_FAILS)"
    fi

    if [ "$FAIL_COUNT" -ge "$MAX_FAILS" ]; then
        # Если мы думали, что всё ОК, а связи нет - спасаем
        if [ "$STATE" = "OK" ]; then
            log_event "INTERNET_LOST: Связь пропала. Запуск экстренного восстановления."
            aggressive_rescue
            STATE="DOWN"
        else
            # Если мы уже в состоянии DOWN, но связи всё еще нет - пробуем еще раз очистить (на всякий случай)
            # Но не частим, раз в 30 секунд
            if [ $((FAIL_COUNT % 30)) -eq 0 ]; then
                log_event "RETRY_RESCUE: Связь всё еще не восстановилась, повторная очистка..."
                aggressive_rescue
            fi
        fi
    fi

    sleep 1
done
