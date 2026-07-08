#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib.sh

log_info "Frappe HRMS — Sync Users from YAML"
log_info "==================================="

require_docker
require_env DB_PASSWORD ADMIN_PASSWORD

SITE=$(get_site)
USERS_YAML="config/users.yaml"

if [[ ! -f "$USERS_YAML" ]]; then
    USERS_YAML="config/users.yaml.example"
    if [[ ! -f "$USERS_YAML" ]]; then
        log_error "Users file not found: config/users.yaml or config/users.yaml.example"
        exit 1
    fi
fi

log_info "Reading users from: $USERS_YAML"

docker compose exec -T backend bench --site "$SITE" console --quiet -c '
import json
import os
import yaml

import frappe
from frappe.core.doctype.user.user import create_contact

yaml_path = "/home/frappe/config/users.yaml"
if not os.path.exists(yaml_path):
    # Try alternative paths
    for p in ["/home/frappe/config/users.yaml", "/home/frappe/users.yaml"]:
        if os.path.exists(p):
            yaml_path = p
            break

if not os.path.exists(yaml_path):
    print("ERROR: users.yaml not found in container")
    exit(1)

with open(yaml_path) as f:
    data = yaml.safe_load(f)

users = data.get("users", [])
if not users:
    print("No users found in config")
    exit(0)

for entry in users:
    email = entry.get("email", "").strip()
    if not email:
        continue

    first_name = entry.get("first_name", email.split("@")[0])
    last_name = entry.get("last_name", "")
    password = entry.get("password", "")
    role = entry.get("role", "System Manager")
    enabled = entry.get("enabled", 1)

    if frappe.db.exists("User", email):
        user = frappe.get_doc("User", email)
        user.first_name = first_name
        user.last_name = last_name
        user.enabled = enabled
        reset = entry.get("reset_password", False)
        if password and reset:
            user.new_password = password
        user.flags.ignore_permissions = True
        user.save()
        print(f"Updated: {email} ({role})")
    else:
        user = frappe.new_doc("User")
        user.email = email
        user.first_name = first_name
        user.last_name = last_name
        user.enabled = enabled
        user.send_welcome_email = 0
        if password:
            user.new_password = password
        user.flags.ignore_permissions = True
        user.append("roles", {"role": role})
        user.insert(ignore_permissions=True)
        print(f"Created: {email} ({role})")

print(f"Synced {len(users)} user(s)")
' 2>/dev/null || {
    log_warn "Direct sync failed, trying fallback method..."
    # Fallback: use bench execute with a Python script
    docker compose cp "$USERS_YAML" backend:/home/frappe/users.yaml
    docker compose exec -T backend bench --site "$SITE" execute /home/frappe/sync_users.py 2>/dev/null || {
        log_error "Sync failed"
        exit 1
    }
}

log_ok "User sync complete"
