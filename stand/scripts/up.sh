#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STAND_DIR="$SCRIPT_DIR/.."

# Учебные пароли стенда (не секреты в реальном смысле, но не коммитим): создаём файл один раз,
# если его нет. Значения см. results/00-summary.md.
SECRETS_ENV="$STAND_DIR/secrets/stand.env"
# Без спецсимволов URL (#@/:%) — FTP_BACKUP_PASSWORD подставляется в ftp:// URL в backup.sh,
# а '#' там обрывает строку как начало fragment. Доменные пароли проходят сложность Samba AD
# (заглавные, строчные, цифры, длина >= 10).
DEFAULTS=(
    WEBAPP_DB_PASSWORD=Webapp2026stand
    FTP_BACKUP_PASSWORD=Backup2026stand
    ARM_SSH_PASSWORD=Arm2026stand
    DC_ADMIN_PASSWORD=DcAdmin2026stand
    DOMAIN_USER_PASSWORD=Domain2026stand
)
touch "$SECRETS_ENV"
for kv in "${DEFAULTS[@]}"; do
    # Дописываем только отсутствующие переменные: уже заданные значения не трогаем.
    if ! grep -q "^${kv%%=*}=" "$SECRETS_ENV"; then
        echo "$kv" >> "$SECRETS_ENV"
        echo "В $SECRETS_ENV добавлена ${kv%%=*} (учебное значение по умолчанию)."
    fi
done

# Базовый образ собирается отдельно: на него ссылаются Dockerfile остальных узлов (FROM gis-base),
# а docker compose build не знает об этой внутренней зависимости между сервисами.
docker build -t gis-base "$STAND_DIR/nodes/base"

docker compose -f "$STAND_DIR/docker-compose.yml" build
docker compose -f "$STAND_DIR/docker-compose.yml" up -d

echo "Стенд gis поднят. Режим МЭ по умолчанию: protect."
