#!/usr/bin/env bash
set -e

echo '=== Configurator: Setting up Frappe site ==='

if [ -f /home/frappe/frappe-bench/sites/$SITE_NAME/site_config.json ]; then
  echo 'Site already exists. Running post-setup...'
  echo "Site exists, skipping setup"
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

  echo 'Applying site configuration...'
  cd /home/frappe/frappe-bench
  echo -e "import sys\nsys.path.insert(0, '/home/frappe')\nimport setup_site\nsetup_site.run()" | \
    bench --site "$SITE_NAME" console

  echo 'Building assets...'
  bench build
fi

echo '=== Configurator complete ==='
