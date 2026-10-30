#!/bin/sh
set -eu
. /usr/local/lib/gis-lib.sh

IF_TRANSIT=$(iface_for_subnet 192.168.50)

ip route replace default via 192.168.50.1 dev "$IF_TRANSIT"
ip route replace 192.168.100.0/24 via 192.168.50.2 dev "$IF_TRANSIT"
ip route replace 192.168.200.0/24 via 192.168.50.4 dev "$IF_TRANSIT"

# WireGuard-интерфейс и правила поднимутся в этапе 04.
exec sleep infinity
