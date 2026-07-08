#!/usr/bin/env bash
set -euo pipefail

HRMS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HRMS_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

require_env() {
    if [[ ! -f .env ]]; then
        log_error ".env file not found. Run: cp .env.example .env && edit .env"
        exit 1
    fi
    set -a
    source .env
    set +a
    local missing=()
    for var in "$@"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required env vars: ${missing[*]}"
        exit 1
    fi
}

get_site() {
    echo "${SITE_NAME:-hrms.example.com}"
}

require_docker() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    if ! docker compose version &>/dev/null; then
        log_error "Docker Compose v2 is not installed"
        exit 1
    fi
}
