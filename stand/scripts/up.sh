#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STAND_DIR="$SCRIPT_DIR/.."

# Учебные пароли стенда (не секреты в реальном смысле, но не коммитим): создаём файл один раз,
# если его нет. Значения см. results/00-summary.md.
SECRETS_ENV="$STAND_DIR/secrets/stand.env"
if [[ ! -f "$SECRETS_ENV" ]]; then
    # Без спецсимволов URL (#@/:%) — FTP_BACKUP_PASSWORD подставляется в ftp:// URL в backup.sh,
    # а '#' там обрывает строку как начало fragment.
    cat > "$SECRETS_ENV" <<'EOF'
WEBAPP_DB_PASSWORD=Webapp2026stand
FTP_BACKUP_PASSWORD=Backup2026stand
ARM_SSH_PASSWORD=Arm2026stand
EOF
    echo "Создан $SECRETS_ENV с учебными паролями по умолчанию."
fi

# Базовый образ собирается отдельно: на него ссылаются Dockerfile остальных узлов (FROM gis-base),
# а docker compose build не знает об этой внутренней зависимости между сервисами.
docker build -t gis-base "$STAND_DIR/nodes/base"

docker compose -f "$STAND_DIR/docker-compose.yml" build
docker compose -f "$STAND_DIR/docker-compose.yml" up -d

echo "Стенд gis поднят. Режим МЭ по умолчанию: protect."
