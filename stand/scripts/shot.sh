#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Использование: $0 <имя> <команда...>" >&2
    exit 1
fi

NAME="$1"
shift
CMD="$*"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GIS_DIR="$SCRIPT_DIR/../.."
SCREENS_DIR="$GIS_DIR/results/screens"
mkdir -p "$SCREENS_DIR"

TXT="$SCREENS_DIR/${NAME}.txt"
PNG="$SCREENS_DIR/${NAME}.png"

{
    echo "$(whoami)@$(hostname):~\$ $CMD"
    bash -c "$CMD" 2>&1 || true
} > "$TXT"

"$GIS_DIR/.venv/bin/python" "$SCRIPT_DIR/render_term.py" "$TXT" "$PNG"

echo "Сохранено: $TXT и $PNG"
