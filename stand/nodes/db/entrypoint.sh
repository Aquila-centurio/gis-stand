#!/bin/sh
set -eu
. /usr/local/lib/gis-lib.sh

IF=$(iface_for_subnet 192.168.200)
ip route replace default via 192.168.200.1 dev "$IF"

# PostgreSQL появится в этапе 02. Пока слушаем 5432 и 22, чтобы проверить прохождение/блокировку МЭ.
nc -lk 22 >/dev/null 2>&1 &
exec nc -lk 5432 >/dev/null 2>&1
