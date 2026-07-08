#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib.sh

log_info "Frappe HRMS Installer"
log_info "====================="

require_docker
require_env DB_PASSWORD ADMIN_PASSWORD

log_info "Step 1: Building custom Docker image with HRMS..."
docker compose build

log_info "Step 2: Starting infrastructure (DB, Redis)..."
docker compose up -d db redis-cache redis-queue redis-socketio
docker compose wait db
docker compose wait redis-cache
docker compose wait redis-queue
docker compose wait redis-socketio

log_info "Step 3: Running configurator (site creation + app install)..."
docker compose up configurator
docker compose wait configurator

log_info "Step 4: Starting all services..."
docker compose up -d

log_info "Step 5: Running health check..."
sleep 10
if docker compose exec -T backend bench --site "$SITE_NAME" console --quiet -c 'print("OK")' 2>/dev/null; then
    log_ok "Site is responsive"
else
    log_warn "Site may still be starting up. Run 'make health' to check."
fi

log_ok "Installation complete!"
log_info "Frontend: https://${SITE_NAME:-hrms.example.com}"
log_info "Admin login: ${HRMS_ADMIN_EMAIL:-admin@example.com} / (password from .env)"
log_info ""
log_info "Next steps:"
log_info "  1. Configure DNS: point ${SITE_NAME:-hrms.example.com} to your server IP"
log_info "  2. Add a Caddy reverse proxy config pointing to hrms-frontend:8080 (see blog post for example)"
log_info "  3. Run 'make health' to verify all services"
