#!/bin/sh
set -eu
. /usr/local/lib/gis-lib.sh

IF=$(iface_for_subnet 198.51.100)
ip route replace default via 198.51.100.1 dev "$IF"

exec python3 -m http.server 80 --directory /srv/www
