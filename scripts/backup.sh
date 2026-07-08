#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib.sh

log_info "Frappe HRMS Backup"
log_info "=================="

require_docker
require_env DB_PASSWORD

SITE=$(get_site)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="backups/$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

log_info "Creating backup for site: $SITE"

docker compose exec -T backend bench --site "$SITE" backup --with-files \
    --backup-path "/home/frappe/frappe-bench/sites/$SITE/private/backups"

log_info "Copying backup files..."
docker compose run --rm --no-deps \
    -v hrms_backups:/backups \
    backend bash -c "
        cp /home/frappe/frappe-bench/sites/$SITE/private/backups/* /backups/ 2>/dev/null || true
    "

docker compose run --rm --no-deps \
    -v hrms_backups:/backups \
    -v "$(pwd)/$BACKUP_DIR:/local" \
    backend bash -c "cp /backups/* /local/ 2>/dev/null || true"

log_info "Backup stored: $BACKUP_DIR"

SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
log_ok "Backup size: $SIZE"

# Retention: keep last N backups
MAX_BACKUPS=${BACKUP_LIMIT:-14}
COUNT=$(ls -dt backups/20* 2>/dev/null | wc -l)
if [[ "$COUNT" -gt "$MAX_BACKUPS" ]]; then
    TO_DELETE=$((COUNT - MAX_BACKUPS))
    log_info "Cleaning old backups (keeping last $MAX_BACKUPS)..."
    ls -dt backups/20* 2>/dev/null | tail -n "$TO_DELETE" | while read -r old; do
        rm -rf "$old"
        log_info "Removed: $old"
    done
fi

log_ok "Backup complete: ${SIZE} total in $BACKUP_DIR"
