#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib.sh

log_info "Frappe HRMS Updater"
log_info "==================="

require_docker
require_env DB_PASSWORD ADMIN_PASSWORD

BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

log_info "Step 1: Creating pre-update backup..."
docker compose exec -T backend bench --site "$SITE_NAME" backup --with-files 2>/dev/null || \
    log_warn "Pre-update backup failed (first install?). Continuing..."

log_info "Step 2: Pulling latest base images..."
docker compose pull

log_info "Step 3: Rebuilding custom image..."
docker compose build --no-cache

log_info "Step 4: Restarting services with new image..."
docker compose up -d --remove-orphans --force-recreate

log_info "Step 5: Running database migrations..."
docker compose exec -T backend bench --site "$SITE_NAME" migrate

log_info "Step 6: Clearing cache and rebuilding assets..."
docker compose exec -T backend bench --site "$SITE_NAME" clear-cache
docker compose exec -T backend bench build

log_info "Step 7: Verifying health..."
if docker compose exec -T backend bench --site "$SITE_NAME" console --quiet -c 'print("OK")' 2>/dev/null; then
    log_ok "Site is healthy after update"
else
    log_error "Site health check failed after update!"
    log_info "Rollback: docker compose down && git checkout <previous> && make install"
    exit 1
fi

log_ok "Update complete!"
