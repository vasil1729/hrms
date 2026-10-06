#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib.sh

log_info "Frappe HRMS — Sync Users via REST API"
log_info "======================================"

# Load API credentials from generated file
API_KEYS_FILE="$(dirname "$0")/../.api_keys.env"
if [[ -f "$API_KEYS_FILE" ]]; then
    set -a
    source "$API_KEYS_FILE"
    set +a
fi

require_env HRMS_API_KEY HRMS_API_SECRET

SITE=$(get_site)
USERS_YAML="config/users.yaml"
API_URL="https://${SITE}/api/resource"
AUTH="Authorization: token ${HRMS_API_KEY}:${HRMS_API_SECRET}"

if [[ ! -f "$USERS_YAML" ]]; then
    USERS_YAML="config/users.yaml.example"
    if [[ ! -f "$USERS_YAML" ]]; then
        log_error "Users file not found: config/users.yaml or config/users.yaml.example"
        exit 1
    fi
fi

log_info "Reading users from: $USERS_YAML"

# Use Python on the host to parse YAML and make API calls
python3 << PYEOF
import json
import os
import sys
import urllib.request
import urllib.error
import urllib.parse
import yaml

SITE = os.environ.get("SITE_NAME", "$SITE")
API_KEY = os.environ.get("HRMS_API_KEY", "${HRMS_API_KEY:-}")
API_SECRET = os.environ.get("HRMS_API_SECRET", "${HRMS_API_SECRET:-}")
BASE = f"https://{SITE}/api/resource"

with open("$USERS_YAML") as f:
    data = yaml.safe_load(f)

users = data.get("users", [])
if not users:
    print("No users found")
    sys.exit(0)


def api(method, path, body=None):
    url = BASE + path
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"token {API_KEY}:{API_SECRET}")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "curl/8.18.0")
    req.add_header("Accept", "*/*")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:300]
        print(f"  HTTP {e.code}: {body}")
        return None
    except urllib.error.URLError as e:
        print(f"  Connection error: {e.reason}")
        return None


for entry in users:
    email = entry.get("email", "").strip()
    if not email:
        continue
    encoded = urllib.parse.quote(email, safe="")

    first_name = entry.get("first_name", email.split("@")[0])
    last_name = entry.get("last_name", "")
    password = entry.get("password", "")
    roles_raw = entry.get("roles") or entry.get("role", "System Manager")
    if isinstance(roles_raw, str):
        roles_raw = [roles_raw]
    enabled = entry.get("enabled", 1)

    roles = [{"role": r} for r in roles_raw]
    payload = {
        "first_name": first_name,
        "last_name": last_name,
        "enabled": enabled,
        "roles": roles,
    }
    if password:
        payload["new_password"] = password

    resp = api("GET", f"/User/{encoded}")
    if resp and "data" in resp:
        result = api("PUT", f"/User/{encoded}", payload)
        if result:
            print(f"  Updated: {email} ({', '.join(roles_raw)})")
    else:
        payload["email"] = email
        payload["send_welcome_email"] = 0
        result = api("POST", "/User", payload)
        if result:
            print(f"  Created: {email} ({', '.join(roles_raw)})")

print(f"Done — {len(users)} user(s) processed")
PYEOF
