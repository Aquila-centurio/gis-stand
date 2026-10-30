#!/bin/bash
# radius: FreeRADIUS. Клиент (NAS) — fw-int (Squid), пользователи — файл users.
set -euo pipefail
. /usr/local/lib/gis-lib.sh

IF_TRANSIT=$(iface_for_subnet 192.168.50)
ip route replace default via 192.168.50.1 dev "$IF_TRANSIT"

RADIUS_SECRET="${RADIUS_SECRET:?нужен RADIUS_SECRET в stand/secrets/stand.env}"
PROXY_USER_PASSWORD="${PROXY_USER_PASSWORD:?нужен PROXY_USER_PASSWORD в stand/secrets/stand.env}"
RADDB=/etc/freeradius/3.0

# Единственный внешний клиент — fw-int (Squid). localhost оставлен из штатного конфига для radtest на самом radius.
CLIENTS=$RADDB/clients.conf
sed -i '/^# gis-begin/,/^# gis-end/d' "$CLIENTS"
cat >> "$CLIENTS" <<EOF
# gis-begin
client fw-int {
	ipv4addr  = 192.168.50.4
	secret    = ${RADIUS_SECRET}
	shortname = fw-int
	# basic_radius_auth (Squid 6.13) не добавляет Message-Authenticator. В режиме auto сервер
	# после первого же запроса с этим атрибутом (radtest) начинает требовать его и молча
	# отбрасывает запросы Squid. Явное no отключает эту защиту от BlastRADIUS для fw-int.
	require_message_authenticator = no
	limit_proxy_state = no
}
# gis-end
EOF

# Учебные учётки для выхода в интернет (пароль один на всех, см. results/00-summary.md).
# guest заведён явно с отказом: учётка есть, но доступ запрещён.
USERS=$RADDB/mods-config/files/authorize
sed -i '/^# gis-begin/,/^# gis-end/d' "$USERS"
TMP=$(mktemp)
{
    echo "# gis-begin"
    for u in archstaff1 archhead sysadmin secadmin; do
        printf '%s\tCleartext-Password := "%s"\n\n' "$u" "$PROXY_USER_PASSWORD"
    done
    printf 'guest\tAuth-Type := Reject\n\tReply-Message := "Guest: доступ в интернет запрещён"\n\n'
    echo "# gis-end"
    cat "$USERS"
} > "$TMP"
cat "$TMP" > "$USERS"
rm -f "$TMP"

chown -R freerad:freerad /var/log/freeradius
# Проверка конфигурации до запуска: при ошибке контейнер падает с понятным сообщением.
freeradius -C -lstdout >/dev/null
exec freeradius -f
