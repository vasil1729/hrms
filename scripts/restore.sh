#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib.sh

log_info "Frappe HRMS Restore"
log_info "==================="

require_docker
require_env DB_PASSWORD

SITE=$(get_site)

if [[ $# -lt 1 ]]; then
    log_error "Usage: $0 <backup-directory>"
    log_info "Available backups:"
    ls -1 backups/
    exit 1
fi

BACKUP_DIR="backups/$1"
if [[ ! -d "$BACKUP_DIR" ]]; then
    log_error "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

log_info "Restoring from: $BACKUP_DIR"

SQL_FILE=$(ls "$BACKUP_DIR"/*-database.sql.gz 2>/dev/null | head -1)
FILES_FILE=$(ls "$BACKUP_DIR"/*-files.tar 2>/dev/null | head -1)
PRIVATE_FILES=$(ls "$BACKUP_DIR"/*-private-files.tar 2>/dev/null | head -1)

if [[ -z "$SQL_FILE" ]]; then
    log_error "No database backup found in $BACKUP_DIR"
    exit 1
fi

log_info "Found:"
[[ -n "$SQL_FILE" ]] && log_info "  Database: $(basename "$SQL_FILE")"
[[ -n "$FILES_FILE" ]] && log_info "  Public files: $(basename "$FILES_FILE")"
[[ -n "$PRIVATE_FILES" ]] && log_info "  Private files: $(basename "$PRIVATE_FILES")"

log_warn "This will OVERWRITE the current site data!"
read -rp "Continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_info "Restore cancelled"
    exit 0
fi

log_info "Step 1: Stopping services..."
docker compose stop backend worker scheduler websocket

log_info "Step 2: Restoring database..."
gunzip -c "$SQL_FILE" | docker compose exec -T db mysql -u root -p"$DB_PASSWORD" "$DB_NAME"

if [[ -n "$FILES_FILE" ]]; then
    log_info "Step 3: Restoring public files..."
    docker compose run --rm --no-deps \
        -v hrms_sites:/sites \
        -v "$(pwd)/$BACKUP_DIR:/backup" \
        backend bash -c "cd /sites/$SITE && tar xf /backup/$(basename "$FILES_FILE")"
fi

if [[ -n "$PRIVATE_FILES" ]]; then
    log_info "Step 4: Restoring private files..."
    docker compose run --rm --no-deps \
        -v hrms_sites:/sites \
        -v "$(pwd)/$BACKUP_DIR:/backup" \
        backend bash -c "cd /sites/$SITE && tar xf /backup/$(basename "$PRIVATE_FILES")"
fi

log_info "Step 5: Restarting services..."
docker compose up -d

log_info "Step 6: Verifying restore..."
sleep 10
if docker compose exec -T backend bench --site "$SITE" console --quiet -c 'print("OK")' 2>/dev/null; then
    log_ok "Restore verified successfully"
else
    log_error "Restore verification failed"
    exit 1
fi

log_ok "Restore complete!"
