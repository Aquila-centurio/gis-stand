#!/bin/sh
set -eu
. /usr/local/lib/gis-lib.sh

IF=$(iface_for_subnet 192.168.100)
ip route replace default via 192.168.100.1 dev "$IF"

: "${WEBAPP_DB_PASSWORD:?нужен пароль webapp в stand/secrets/stand.env}"

mkdir -p /var/run/apache2 /var/lock/apache2
exec apache2ctl -D FOREGROUND
