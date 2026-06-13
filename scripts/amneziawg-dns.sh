#!/bin/sh
MODE=$1
if [ "$MODE" = "on" ]; then
    uci set network.wan.peerdns='0'
    uci set network.wan.dns='8.8.8.8 1.1.1.1'
    uci commit network
    /etc/init.d/dnsmasq restart
elif [ "$MODE" = "off" ]; then
    uci set network.wan.peerdns='1'
    uci del network.wan.dns
    uci commit network
    /etc/init.d/dnsmasq restart
fi
