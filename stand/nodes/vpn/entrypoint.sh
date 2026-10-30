#!/bin/sh
set -eu
. /usr/local/lib/gis-lib.sh

IF_TRANSIT=$(iface_for_subnet 192.168.50)

ip route replace default via 192.168.50.1 dev "$IF_TRANSIT"
ip route replace 192.168.100.0/24 via 192.168.50.2 dev "$IF_TRANSIT"
ip route replace 192.168.200.0/24 via 192.168.50.4 dev "$IF_TRANSIT"

nft -f /etc/nft/vpn.nft

# Ключи хранятся на смонтированном с хоста томе stand/secrets/wg (не в git, не в образе) и
# генерируются один раз при первом запуске — идемпотентно, переживает docker compose down/up.
# bad-client — ключ, который никогда не попадёт в peer-лист сервера: используется в этапе 04
# для проверки «клиент с неверным ключом не получает handshake».
WG_DIR=/secrets/wg
mkdir -p "$WG_DIR"
umask 077
for name in server client bad-client; do
    if [ ! -f "$WG_DIR/$name.key" ]; then
        wg genkey > "$WG_DIR/$name.key"
        wg pubkey < "$WG_DIR/$name.key" > "$WG_DIR/$name.pub"
    fi
done

mkdir -p /etc/wireguard
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $(cat "$WG_DIR/server.key")

[Peer]
# client — легитимный удалённый пользователь (prompts/04-vpn.md)
PublicKey = $(cat "$WG_DIR/client.pub")
AllowedIPs = 10.8.0.2/32
EOF
chmod 600 /etc/wireguard/wg0.conf

wg-quick up wg0

exec sleep infinity
