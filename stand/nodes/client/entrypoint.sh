#!/bin/sh
set -eu
. /usr/local/lib/gis-lib.sh

IF=$(iface_for_subnet 198.51.100)
ip route replace default via 198.51.100.1 dev "$IF"
ip route replace 192.168.0.0/16 via 198.51.100.1 dev "$IF"

# Конфиги WireGuard готовятся сразу (ключи берутся из тома stand/secrets/wg, который
# заполняет vpn), но сам туннель не поднимается автоматически — это делает пользователь
# вручную (wg-quick up/down wg0), чтобы показать доступ до и после подключения (этап 04).
/usr/local/bin/wg-prepare.sh || echo "wg-prepare: ключи vpn ещё не готовы, повторите позже вручную" >&2

exec sleep infinity
