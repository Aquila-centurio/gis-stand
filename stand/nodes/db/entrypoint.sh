#!/bin/sh
set -eu
. /usr/local/lib/gis-lib.sh

IF=$(iface_for_subnet 192.168.200)
ip route replace default via 192.168.200.1 dev "$IF"

PGVER=$(ls /etc/postgresql)
PGCONF=/etc/postgresql/$PGVER/main
DATADIR=/var/lib/postgresql/$PGVER/main
BIN=/usr/lib/postgresql/$PGVER/bin

# Слушаем только на своём адресе интранета и на localhost, не на всех интерфейсах.
sed -i "s/^#\?listen_addresses.*/listen_addresses = '192.168.200.10,localhost'/" "$PGCONF/postgresql.conf"

cat > "$PGCONF/pg_hba.conf" <<'EOF'
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            md5
# webapp подключается к site только с адреса web (dmz .10)
host    site            webapp          192.168.100.10/32       md5
host    all             all             0.0.0.0/0               reject
EOF
chown postgres:postgres "$PGCONF/pg_hba.conf"
chmod 640 "$PGCONF/pg_hba.conf"

# Временный запуск для инициализации (idempotent: CREATE ... IF NOT EXISTS / GRANT повторно безопасны).
su postgres -c "$BIN/pg_ctl -D $DATADIR -l /var/log/postgresql/startup.log -o '-c config_file=$PGCONF/postgresql.conf' -w start"

WEBAPP_DB_PASSWORD="${WEBAPP_DB_PASSWORD:?нужен пароль webapp в stand/secrets/stand.env}"

su postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='site'\"" | grep -q 1 \
    || su postgres -c "psql -c 'CREATE DATABASE site OWNER postgres'"

su postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='webapp'\"" | grep -q 1 \
    || su postgres -c "psql -c \"CREATE ROLE webapp LOGIN\""
su postgres -c "psql -c \"ALTER ROLE webapp WITH PASSWORD '$WEBAPP_DB_PASSWORD'\""

su postgres -c "psql -d site -v ON_ERROR_STOP=1 -f /usr/local/share/gis-db-init.sql"

su postgres -c "$BIN/pg_ctl -D $DATADIR -m fast -w stop"

exec su postgres -c "$BIN/postgres -D $DATADIR -c config_file=$PGCONF/postgresql.conf"
