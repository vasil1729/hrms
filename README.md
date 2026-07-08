# Frappe HRMS — Self-Hosted Deployment

Production-grade Docker Compose deployment of [Frappe HRMS](https://github.com/frappe/hrms) on Ubuntu 24.04 with Caddy reverse proxy, Cloudflare DNS, and automated backups.

## Architecture

```
┌─────────────┐     ┌──────────┐     ┌─────────────────────┐
│  Internet   │────▶│  Caddy   │────▶│  Frappe Backend     │
│  (HTTPS)    │     │  (Proxy) │     │  (Gunicorn :8000)   │
└─────────────┘     └──────────┘     └──────────┬──────────┘
                                                │
                    ┌───────────────────────────┼───────────┐
                    │                           │           │
              ┌─────▼─────┐            ┌────────▼────┐ ┌───▼────┐
              │  MariaDB  │            │    Redis    │ │Worker  │
              │  (Port    │            │  (Cache,    │ │ x N    │
              │   3306)   │            │  Queue, IO) │ │        │
              └───────────┘            └─────────────┘ └────────┘
```

Services run on an internal Docker network. Only the backend (via Caddy) is publicly exposed.

## Prerequisites

- Ubuntu 24.04 LTS
- Docker Engine 24+ and Docker Compose v2
- Git
- Caddy with Cloudflare DNS module (for TLS automation)
- Cloudflare-managed domain
- SSH access to server
- WireGuard for private administrative access

## Quick Start

```bash
# Clone or copy this project to your server
cd hrms

# Create environment file
cp .env.example .env

# Edit .env — set strong passwords
nano .env

# Build and deploy
make install

# Check health
make health
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SITE_NAME` | Frappe site domain | `hrms.example.com` |
| `DB_NAME` | MariaDB database name | `hrms` |
| `DB_PASSWORD` | MariaDB root password | **(required)** |
| `ADMIN_PASSWORD` | Frappe admin password | **(required)** |
| `WORKERS` | Gunicorn worker count | `4` |
| `WORKER_REPLICAS` | Background worker replicas | `2` |
| `BACKUP_LIMIT` | Backup retention count | `14` |
| `ERPNext_VERSION` | Base image version tag | `v15.41.0` |

### DNS

Point `hrms.example.com` to your server IP:

```
hrms.example.com.  A  <your-server-ip>
```

### Caddy Reverse Proxy

Add the configuration from `compose/caddy/Caddyfile` to your existing Caddy setup. The config handles:

- Automatic TLS via Cloudflare DNS challenge
- Static asset caching (immutable, 1 year)
- WebSocket support for Frappe real-time
- Security headers (HSTS, CSP, etc.)
- Gzip/Brotli compression

### Allowed Users

Edit `config/users.yaml` to control who can access the system. Self-signup is disabled.

```yaml
users:
  - email: admin@example.com
    first_name: Dev
    last_name: Admin
    password: "<replace-with-strong-password>"
    role: System Manager
    enabled: 1
```

Run `make sync-users` to apply user changes without restarting.

## Operations

### Makefile Commands

| Command | Description |
|---------|-------------|
| `make install` | Build images and start all services |
| `make build` | Rebuild Docker images |
| `make update` | Full update: backup, pull, rebuild, migrate, restart |
| `make backup` | Create site backup (DB + files) |
| `make restore FILE=... BACKUPS_DIR=...` | Restore from backup |
| `make health` | Run comprehensive health checks |
| `make logs` | Follow container logs |
| `make logs [service]` | Follow logs for specific service |
| `make shell` | Open bash in backend container |
| `make db-shell` | Open MySQL CLI |
| `make sync-users` | Sync users from `config/users.yaml` |
| `make down` | Stop all services |
| `make reload` | Restart all services without recreating |

### Backup

Automated backups:

```bash
# Manual backup
./scripts/backup.sh

# Cron — daily at 02:00, weekly at 03:00 on Sunday
0 2 * * * /path/to/hrms/scripts/backup.sh
0 3 * * 0 /path/to/hrms/scripts/backup.sh
```

Backups include:
- Full database dump (gzipped SQL)
- Public files (tar archive)
- Private files (tar archive)

Retention: keeps last `BACKUP_LIMIT` backups (default 14).

### Restore

```bash
./scripts/restore.sh 20260708_020000
```

This restores the site to the state captured in that backup. The service will be briefly unavailable during restore.

### Update

```bash
make update
```

Update process:
1. Creates pre-update backup
2. Pulls latest base Docker images
3. Rebuilds custom image with `--no-cache`
4. Starts containers with new images
5. Runs `bench migrate` for schema/data migrations
6. Clears cache and rebuilds static assets
7. Verifies site health

**Rollback**: `git checkout <previous-version> && make install`

## Security

| Decision | Rationale |
|----------|-----------|
| Containers run as non-root (`frappe` user) | Reduces blast radius of container compromise |
| All capabilities dropped by default | Minimal privilege principle; only `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID` added for MariaDB and Redis |
| `no-new-privileges:true` | Prevents privilege escalation via `suid` binaries |
| Internal Docker network for DB/Redis | Database and cache are not accessible from outside the Docker network |
| `read_only: true` | Not enabled by default (Frappe writes to filesystem), but volumes are used for all persistent data |
| Health checks on every service | Ensures Docker restarts unresponsive containers automatically |
| Resource limits (`mem_limit`) | Prevents runaway containers from starving the host |
| Self-signup disabled | Only users listed in `config/users.yaml` can access the system |
| HSTS + security headers | Enforced at the Caddy reverse proxy level |
| Automatic backups | Data loss prevention with configurable retention |

## Monitoring

### Built-in

- Docker health checks on every service
- `make health` — comprehensive status report
- Container logs via `docker compose logs`

### Optional (recommended)

- **Prometheus** + **cAdvisor**: Container-level metrics
- **Grafana**: Dashboards for system health dashboards
- **Loki** + **Promtail**: Centralized log aggregation

These are not included by default to keep the deployment simple, but can be added by connecting to the same Docker network.

## Upgrades

### Version Pinning

The `ERPNext_VERSION` build argument pins the base image version:

```dockerfile
ARG ERPNext_VERSION=v15.41.0
FROM frappe/erpnext:${ERPNext_VERSION}
```

To upgrade to a newer version:
1. Update `ERPNext_VERSION` in `.env`
2. Run `make update`

### Frappe App Updates

The HRMS app is cloned at image build time. To update HRMS to a newer branch/commit:
1. Update the branch/tag in `Dockerfile`
2. Run `make update`

### Rollback

```bash
# Revert to previous image tag
export ERPNext_VERSION=v15.40.0
make build
docker compose up -d
```

## Troubleshooting

### Site not accessible

```bash
# Check container status
docker compose ps

# Check backend logs
docker compose logs backend

# Check site health from within container
docker compose exec backend bench --site hrms.example.com console
```

### Database connection errors

```bash
# Verify MariaDB is healthy
docker compose exec db mysqladmin ping

# Check connection from backend
docker compose exec backend bench --site hrms.example.com console
```

### Background jobs not running

```bash
# Check worker and scheduler status
docker compose ps worker scheduler

# View worker logs
docker compose logs worker

# Check Redis queue
docker compose exec redis-queue redis-cli LLEN rq:queue:default
```

### Permission denied errors

The backup and restore scripts need Docker socket access. Ensure your user is in the `docker` group:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

## File Layout

```
hrms/
├── compose.yaml          # Docker Compose orchestrator
├── Dockerfile            # Custom image with HRMS
├── .env.example          # Environment template
├── Makefile              # Operation shortcuts
├── compose/
│   └── caddy/
│       └── Caddyfile     # Reverse proxy configuration
├── config/
│   ├── users.yaml        # Allowed users list
│   ├── site_config.json  # Frappe site overrides
│   └── setup-site.py     # First-run configuration script
├── scripts/
│   ├── install.sh        # First-time deployment
│   ├── update.sh         # Update with rollback
│   ├── backup.sh         # Database + files backup
│   ├── restore.sh        # Restore from backup
│   ├── logs.sh           # Log viewer
│   ├── health.sh         # Health check
│   ├── sync-users.sh     # Sync users from YAML
│   └── lib.sh            # Shared functions
├── volumes/              # Docker volume mount points
├── backups/              # Local backup storage
├── logs/                 # Log directory
└── README.md
```

## License

MIT
