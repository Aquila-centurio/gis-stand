#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STAND_DIR="$SCRIPT_DIR/.."

# Базовый образ собирается отдельно: на него ссылаются Dockerfile остальных узлов (FROM gis-base),
# а docker compose build не знает об этой внутренней зависимости между сервисами.
docker build -t gis-base "$STAND_DIR/nodes/base"

docker compose -f "$STAND_DIR/docker-compose.yml" build
docker compose -f "$STAND_DIR/docker-compose.yml" up -d

echo "Стенд gis поднят. Режим МЭ по умолчанию: protect."
