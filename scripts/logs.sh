#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib.sh

SERVICE="${1:-}"
LINES="${2:-100}"

if [[ -n "$SERVICE" ]]; then
    docker compose logs -f --tail="$LINES" "$SERVICE"
else
    docker compose logs -f --tail="$LINES"
fi
