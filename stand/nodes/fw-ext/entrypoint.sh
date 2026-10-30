#!/bin/sh
set -eu
. /usr/local/lib/gis-lib.sh

IF_TRANSIT=$(iface_for_subnet 192.168.50)

# fw-ext — верхний узел, у него нет default route, только явные маршруты в transit.
# Docker всё равно пытается поставить свой default через шлюз bridge-сети (не доверяем ему) — убираем.
ip route del default 2>/dev/null || true
ip route replace 192.168.100.0/24 via 192.168.50.2 dev "$IF_TRANSIT"
ip route replace 192.168.200.0/24 via 192.168.50.4 dev "$IF_TRANSIT"
ip route replace 10.8.0.0/24 via 192.168.50.3 dev "$IF_TRANSIT"

MODE=$(gis_read_mode)
gis_write_mode "$MODE"
nft -f "/etc/nft/fw-ext-${MODE}.nft"

exec sleep infinity
