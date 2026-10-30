#!/bin/sh
set -eu
. /usr/local/lib/gis-lib.sh

IF_TRANSIT=$(iface_for_subnet 192.168.50)

ip route replace default via 192.168.50.1 dev "$IF_TRANSIT"
ip route replace 192.168.100.0/24 via 192.168.50.2 dev "$IF_TRANSIT"
ip route replace 10.8.0.0/24 via 192.168.50.3 dev "$IF_TRANSIT"

MODE=$(gis_read_mode)
gis_write_mode "$MODE"
nft -f "/etc/nft/fw-int-${MODE}.nft"

# Squid: конфиг хелпера RADIUS с общим секретом (секрет только из stand.env, в образ не попадает).
RADIUS_SECRET="${RADIUS_SECRET:?нужен RADIUS_SECRET в stand/secrets/stand.env}"
umask 027
printf 'server 192.168.50.5\nsecret %s\nidentifier fw-int\n' "$RADIUS_SECRET" > /etc/squid/radius.conf
chown root:proxy /etc/squid/radius.conf
umask 022

mkdir -p /var/log/squid /var/spool/squid
chown proxy:proxy /var/log/squid /var/spool/squid
rm -f /run/squid.pid
squid -k parse -f /etc/squid/squid.conf
exec squid -N -f /etc/squid/squid.conf
