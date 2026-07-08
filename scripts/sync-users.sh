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

# Copy users.yaml into the container
docker compose cp "$USERS_YAML" backend:/home/frappe/users.yaml

# Generate and run sync script
docker compose exec -T backend bash -c "cat > /tmp/sync_users.py << 'PYEOF'
import os
import yaml

import frappe

yaml_path = '/home/frappe/users.yaml'
if not os.path.exists(yaml_path):
    print('ERROR: users.yaml not found in container')
    exit(1)

with open(yaml_path) as f:
    data = yaml.safe_load(f)

users = data.get('users', [])
if not users:
    print('No users found in config')
    exit(0)

for entry in users:
    email = entry.get('email', '').strip()
    if not email:
        continue

    first_name = entry.get('first_name', email.split('@')[0])
    last_name = entry.get('last_name', '')
    password = entry.get('password', '')
    roles_raw = entry.get('roles') or entry.get('role', 'System Manager')
    if isinstance(roles_raw, str):
        roles_raw = [roles_raw]
    enabled = entry.get('enabled', 1)

    if frappe.db.exists('User', email):
        frappe.db.set_value('User', email, 'first_name', first_name)
        frappe.db.set_value('User', email, 'last_name', last_name)
        frappe.db.set_value('User', email, 'enabled', enabled)
        if password and entry.get('reset_password', False):
            frappe.db.set_value('User', email, 'new_password', password)
        frappe.db.delete('Has Role', {'parent': email, 'parenttype': 'User'})
        for r in roles_raw:
            rdoc = frappe.get_doc({
                'doctype': 'Has Role',
                'parent': email,
                'parenttype': 'User',
                'parentfield': 'roles',
                'role': r,
            })
            rdoc.flags.ignore_permissions = True
            rdoc.insert()
        frappe.db.commit()
        frappe.clear_cache(user=email)
        print('Updated: %s (%s)' % (email, ', '.join(roles_raw)))
    else:
        user = frappe.new_doc('User')
        user.email = email
        user.first_name = first_name
        user.last_name = last_name
        user.enabled = enabled
        user.send_welcome_email = 0
        if password:
            user.new_password = password
        user.flags.ignore_permissions = True
        for r in roles_raw:
            user.append('roles', {'role': r})
        user.insert(ignore_permissions=True)
        print('Created: %s (%s)' % (email, ', '.join(roles_raw)))

frappe.db.commit()
print('Synced %d user(s)' % len(users))
PYEOF
bench --site $SITE console < /tmp/sync_users.py"

log_ok "User sync complete"
