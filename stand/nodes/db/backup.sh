#!/bin/sh
# Ручной запуск бэкапа: pg_dump базы site -> загрузка на ftp (backup.sh без аргументов).
set -eu

FTP_BACKUP_PASSWORD="${FTP_BACKUP_PASSWORD:?нужен пароль ftp в stand/secrets/stand.env}"

TS=$(date +%Y%m%d-%H%M%S)
DUMP="/tmp/site-$TS.sql"

su postgres -c "pg_dump site" > "$DUMP"
curl -sS --ftp-pasv -T "$DUMP" "ftp://ftpbackup:${FTP_BACKUP_PASSWORD}@192.168.100.11/site-$TS.sql"
rm -f "$DUMP"

echo "Бэкап загружен на ftp: site-$TS.sql"
