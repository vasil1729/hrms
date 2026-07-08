.PHONY: install update backup restore logs health shell db-shell init build down reload

install: build
	docker compose up -d

build:
	docker compose build

update: backup
	docker compose pull
	docker compose build --no-cache
	docker compose up -d --remove-orphans
	@echo "Running migrations..."
	docker compose exec -T backend bench --site $$(grep SITE_NAME .env | cut -d= -f2) migrate
	@echo "Update complete. Verify health with 'make health'"

backup:
	@echo "Creating backup..."
	@mkdir -p backups
	docker compose exec -T backend bench --site $$(grep SITE_NAME .env | cut -d= -f2) backup --with-files
	@echo "Backup stored in sites volume and copied to ./backups/"
	docker compose run --rm --no-deps -v backups:/backups backend bash -c "cp /home/frappe/frappe-bench/sites/*/private/backups/* /backups/ 2>/dev/null || true"
	@echo "Backup complete"

restore:
	@echo "Usage: make restore FILE=path/to/sql-file BACKUPS_DIR=path/to/backups-dir"
	@test -n "$(FILE)" || (echo "ERROR: Specify FILE=path-to-backup.sql"; exit 1)
	@test -n "$(BACKUPS_DIR)" || (echo "ERROR: Specify BACKUPS_DIR=path-to-private-backups"; exit 1)
	docker compose run --rm backend bash -c "bench --site $$(grep SITE_NAME .env | cut -d= -f2) restore --with-public-files $$BACKUPS_DIR/$(FILE)"

logs:
	docker compose logs -f --tail=100 $(filter-out $@,$(MAKECMDGOALS))

health:
	@echo "=== Frappe HRMS Health Check ==="
	@docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "--- Service Health ---"
	@docker compose ps --format "{{.Name}}" | while read svc; do \
		status=$$(docker compose ps --format "{{.Status}}" $$svc); \
		echo "  $$svc: $$status"; \
	done

shell:
	docker compose exec backend bash

db-shell:
	docker compose exec db mysql -u root -p${DB_PASSWORD} ${DB_NAME}

init:
	cp -n .env.example .env || true
	@echo "Edit .env with your secrets, then run 'make install'"

down:
	docker compose down

reload:
	docker compose restart

%:
	@:
