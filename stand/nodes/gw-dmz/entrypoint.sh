#!/bin/sh
set -eu
. /usr/local/lib/gis-lib.sh

IF_TRANSIT=$(iface_for_subnet 192.168.50)

ip route replace default via 192.168.50.1 dev "$IF_TRANSIT"
ip route replace 10.8.0.0/24 via 192.168.50.3 dev "$IF_TRANSIT"
ip route replace 192.168.200.0/24 via 192.168.50.4 dev "$IF_TRANSIT"

MODE=$(gis_read_mode)
gis_write_mode "$MODE"
nft -f "/etc/nft/gw-dmz-${MODE}.nft"

exec sleep infinity
