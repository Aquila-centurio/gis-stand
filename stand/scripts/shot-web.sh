#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Использование: $0 <имя> <url>" >&2
    exit 1
fi

NAME="$1"
URL="$2"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GIS_DIR="$SCRIPT_DIR/../.."
SCREENS_DIR="$GIS_DIR/results/screens"
mkdir -p "$SCREENS_DIR"

# --no-sandbox: полноценный sandbox chromium требует доп. возможностей ядра (userns/seccomp),
# которых у контейнера нет (и не добавляем ради --privileged); client изолирован docker-сетями,
# риск приемлем для учебного стенда.
docker exec gis-client chromium \
    --headless=new --disable-gpu --no-sandbox \
    --ignore-certificate-errors --window-size=1280,900 \
    --screenshot=/tmp/shot-web.png "$URL"

docker cp gis-client:/tmp/shot-web.png "$SCREENS_DIR/${NAME}.png"
docker exec gis-client rm -f /tmp/shot-web.png

echo "Сохранено: $SCREENS_DIR/${NAME}.png"
