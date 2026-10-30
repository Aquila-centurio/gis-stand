#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
if [[ "$MODE" != "protect" && "$MODE" != "audit" ]]; then
    echo "Использование: $0 protect|audit" >&2
    exit 1
fi

# Три межсетевых экрана стенда (vpn и radius своих ACL не имеют).
for role in fw-ext gw-dmz fw-int; do
    echo "== $role -> $MODE =="
    docker exec "gis-$role" sh -c "mkdir -p /etc/gis && echo $MODE > /etc/gis/mode && nft -f /etc/nft/${role}-${MODE}.nft"
done

echo "Режим МЭ переключён на: $MODE"
