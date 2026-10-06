#!/usr/bin/env bash
set -e

echo '=== Configurator: Setting up Frappe site ==='

if [ -f /home/frappe/frappe-bench/sites/$SITE_NAME/site_config.json ]; then
  echo 'Site already exists. Running post-setup...'
else
  echo "Creating new site: $SITE_NAME"
  bench new-site \
    --force \
    --db-name "$DB_NAME" \
    --db-host "$DB_HOST" \
    --db-port "$DB_PORT" \
    --mariadb-root-password "$DB_PASSWORD" \
    --admin-password "$ADMIN_PASSWORD" \
    --no-mariadb-socket \
    "$SITE_NAME"

  echo 'Installing ERPNext...'
  bench --site "$SITE_NAME" install-app erpnext

  echo 'Installing HRMS...'
  bench --site "$SITE_NAME" install-app hrms

  echo 'Building assets...'
  bench build

  echo 'Copying static assets from apps...'
  for app in frappe erpnext hrms; do
    src="/home/frappe/frappe-bench/apps/$app/$app/public"
    dst="/home/frappe/frappe-bench/sites/assets/$app"
    for subdir in icons images sounds js html css; do
      if [ -d "$src/$subdir" ]; then
        mkdir -p "$dst/$subdir"
        cp -r "$src/$subdir"/* "$dst/$subdir/" 2>/dev/null || true
      fi
    done
  done
fi

echo 'Configuring Redis connections...'
cat > /home/frappe/frappe-bench/sites/common_site_config.json << 'EOF'
{
  "redis_cache": "redis://redis-cache:6379",
  "redis_queue": "redis://redis-queue:6379",
  "redis_socketio": "redis://redis-socketio:6379"
}
EOF

echo 'Applying site configuration...'
cd /home/frappe/frappe-bench
cat > /tmp/setup_script.py << 'PYEOF'
import sys
sys.path.insert(0, '/home/frappe')
import setup_site
setup_site.run()
PYEOF
bench --site "$SITE_NAME" console < /tmp/setup_script.py

# Print API keys path for sync-users.sh
KEYS_FILE="/home/frappe/frappe-bench/sites/api_keys.json"
if [ -f "$KEYS_FILE" ]; then
  echo "API keys generated at: $KEYS_FILE"
  echo "Run on host to save: docker compose exec backend cat $KEYS_FILE > ../.api_keys.env"
fi

echo '=== Configurator complete ==='
