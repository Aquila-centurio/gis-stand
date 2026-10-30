#!/bin/sh
set -eu
. /usr/local/lib/gis-lib.sh

IF_TRANSIT=$(iface_for_subnet 192.168.50)
ip route replace default via 192.168.50.1 dev "$IF_TRANSIT"

# FreeRADIUS поднимется в этапе 05.
exec sleep infinity
