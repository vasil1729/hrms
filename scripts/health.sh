#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib.sh

EXIT_CODE=0

echo ""
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}  Frappe HRMS — Health Check${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

require_docker

echo -e "${YELLOW}Container Status:${NC}"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo -e "${YELLOW}Service Health Checks:${NC}"
for svc in db redis-cache redis-queue redis-socketio configurator backend worker scheduler websocket; do
    STATUS=$(docker compose ps --format "{{.Status}}" "$svc" 2>/dev/null || echo "not found")
    NAME=$(docker compose ps --format "{{.Name}}" "$svc" 2>/dev/null || echo "$svc")
    if echo "$STATUS" | grep -q "Up"; then
        echo -e "  ${GREEN}✓${NC} $svc — running"
    elif echo "$STATUS" | grep -q "Exit 0"; then
        echo -e "  ${GREEN}✓${NC} $svc — completed (configurator)"
    else
        echo -e "  ${RED}✗${NC} $svc — $STATUS"
        EXIT_CODE=1
    fi
done
echo ""

SITE=$(get_site)
echo -e "${YELLOW}Site Health:${NC}"
if docker compose exec -T backend bench --site "$SITE" console --quiet -c '
    import frappe
    print(f"Site: {frappe.local.site}")
    print(f"DB: {frappe.db.get_value(\"System Settings\", \"System Settings\", \"timezone\")}")
    print(f"Users: {frappe.db.count(\"User\", {\"enabled\": 1})}")
    print(f"HRMS installed: {\"hrms\" in frappe.get_installed_apps()}")
' 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Site responsive"
else
    echo -e "  ${RED}✗${NC} Site not responding"
    EXIT_CODE=1
fi
echo ""

echo -e "${YELLOW}Redis Connectivity:${NC}"
for redis_svc in redis-cache redis-queue redis-socketio; do
    if docker compose exec -T "$redis_svc" redis-cli ping 2>/dev/null | grep -q "PONG"; then
        echo -e "  ${GREEN}✓${NC} $redis_svc — connected"
    else
        echo -e "  ${RED}✗${NC} $redis_svc — not responding"
        EXIT_CODE=1
    fi
done
echo ""

echo -e "${YELLOW}Background Jobs:${NC}"
if docker compose exec -T backend bench --site "$SITE" console --quiet -c '
    import frappe
    from frappe.utils.background_jobs import get_jobs
    jobs = get_jobs(site=frappe.local.site)
    print(f"Queued: {len(jobs.get(\"queued\", []))}")
    print(f"Running: {len(jobs.get(\"running\", []))}")
    print(f"Failed: {len(jobs.get(\"failed\", []))}")
' 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Job queue accessible"
else
    echo -e "  ${RED}✗${NC} Cannot query jobs"
fi
echo ""

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo -e "${GREEN}All checks passed.${NC}"
else
    echo -e "${RED}Some checks failed.${NC}"
fi
echo ""

exit $EXIT_CODE
