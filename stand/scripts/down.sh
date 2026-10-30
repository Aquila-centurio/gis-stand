#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STAND_DIR="$SCRIPT_DIR/.."

docker compose -f "$STAND_DIR/docker-compose.yml" down -v
