#!/bin/sh
set -eu
. /usr/local/lib/gis-lib.sh

IF=$(iface_for_subnet 192.168.100)
ip route replace default via 192.168.100.1 dev "$IF"

# vsftpd появится в этапе 02.
exec sleep infinity
