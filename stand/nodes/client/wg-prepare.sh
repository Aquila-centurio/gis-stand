#!/bin/sh
# Готовит конфиги WireGuard (wg0.conf — рабочий, wg0-badkey.conf — незарегистрированный ключ
# для проверки «клиент с неверным ключом не получает handshake»), но не поднимает интерфейс —
# это делает пользователь вручную (wg-quick up/down wg0), чтобы показать разницу до/после туннеля.
set -eu

WG_DIR=/secrets/wg
mkdir -p /etc/wireguard
umask 077

wait_key() {
    i=0
    while [ ! -f "$WG_DIR/$1" ] && [ "$i" -lt 30 ]; do
        sleep 1
        i=$((i + 1))
    done
    [ -f "$WG_DIR/$1" ]
}

wait_key server.pub
wait_key client.key

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $(cat "$WG_DIR/client.key")
Address = 10.8.0.2/32

[Peer]
PublicKey = $(cat "$WG_DIR/server.pub")
Endpoint = 198.51.100.1:51820
AllowedIPs = 192.168.200.0/24, 10.8.0.0/24
PersistentKeepalive = 25
EOF
chmod 600 /etc/wireguard/wg0.conf

if wait_key bad-client.key; then
    cat > /etc/wireguard/wg0-badkey.conf <<EOF
[Interface]
PrivateKey = $(cat "$WG_DIR/bad-client.key")
Address = 10.8.0.3/32

[Peer]
# PublicKey сервера настоящий, но этого ключа клиента нет в peer-листе сервера —
# handshake не пройдёт (проверка в prompts/04-vpn.md)
PublicKey = $(cat "$WG_DIR/server.pub")
Endpoint = 198.51.100.1:51820
AllowedIPs = 192.168.200.0/24, 10.8.0.0/24
PersistentKeepalive = 25
EOF
    chmod 600 /etc/wireguard/wg0-badkey.conf
fi
