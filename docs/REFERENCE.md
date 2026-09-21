# Inception — Technical Reference

Complete technical guide covering all core concepts, design decisions, and operational requirements of the Inception infrastructure.

---

## Table of Contents
1. [Docker Core Concepts](#1-docker-core-concepts)
2. [HTTPS & TLS](#2-https--tls)
3. [WordPress & PHP-FPM](#3-wordpress--php-fpm)
4. [MariaDB](#4-mariadb)
5. [Persistence & Volumes](#5-persistence--volumes)
6. [Configuration Changes](#6-making-configuration-changes)
7. [Secrets vs Environment Variables](#7-secrets-vs-environment-variables)
8. [Process Management & PID 1](#8-process-management--pid-1)
9. [Makefile & Orchestration](#9-makefile--orchestration)
10. [Bonus Services](#10-bonus-services)
11. [Critical Requirements at a Glance](#11-critical-requirements-at-a-glance)

---

## 1. Docker Core Concepts

### What is Docker?

Docker is a platform that packages and runs applications inside isolated environments called **containers**. A container bundles an application with everything it needs to run — code, libraries, system tools, configuration files — so it runs identically on any machine.

Docker is not a virtual machine. Containers run directly on the host Linux kernel using two kernel features:

1. **Namespaces** — isolate what a process can *see*:
   - `pid`: The container gets its own process tree. The first process inside is PID 1.
   - `net`: The container gets its own network interfaces, IP, and port space.
   - `mnt`: The container gets its own filesystem view.
   - `uts`: The container gets its own hostname.

2. **Control Groups (cgroups)** — limit what a process can *use*: CPU, RAM, disk I/O, network bandwidth.

### What is a Docker Image?

A Docker image is a **read-only, layered filesystem snapshot** containing everything needed to run a service: the OS base, installed packages, config files, and application code.

Each instruction in a `Dockerfile` adds a **layer**:
```dockerfile
FROM debian:bookworm         # Layer 1: Base OS
RUN apt-get update && \      # Layer 2: Install packages (combined to keep cleanup in same layer)
    apt-get install -y nginx && \
    rm -rf /var/lib/apt/lists/*
COPY nginx.conf /etc/nginx/  # Layer 3: Config file
ENTRYPOINT ["nginx"]
```

Layers are **cached** — unchanged instructions reuse their cached layer, making rebuilds fast. Images are **immutable** — you don't modify a running image, you build a new one.

### What is a Docker Container?

A container is a **running instance of an image**. When Docker starts a container:
1. Takes the read-only image layers.
2. Adds a thin **writable layer** on top (the container layer, temporary).
3. Creates isolated namespaces.
4. Launches the `ENTRYPOINT` process.

Container writes are lost when the container is removed — data that needs to outlive the container must be in a volume.

> **Image vs Container**: An image is a blueprint (class). A container is a live instance (object). You can run many containers from one image.

### What is Docker Compose?

Docker Compose manages **multi-container applications** from a single `docker-compose.yml` file. Instead of running `docker run` with long flag lists for each service, the YAML file declares the complete infrastructure:

- **Services**: each container with its build context, image name, restart policy, dependencies
- **Networks**: the virtual networks connecting containers (`inception_net`)
- **Volumes**: persistent storage definitions
- **Secrets**: sensitive file mounts
- **Environment**: configuration loaded from `.env`

Key commands:

| Command | Action |
|---|---|
| `docker compose build` | Build all images from their Dockerfiles |
| `docker compose up -d` | Create networks/volumes, start all containers in background |
| `docker compose down` | Stop and remove containers and network (volumes kept) |
| `docker compose down -v` | Same, also removes volumes |
| `docker compose ps` | Status of all services |

### Docker vs Virtual Machines

| | Virtual Machine | Docker Container |
|---|---|---|
| **Isolation** | Hardware-level (separate kernel) | OS-level (shared kernel, namespaces) |
| **Size** | Gigabytes (full OS) | Megabytes (app + dependencies) |
| **Boot time** | Minutes | Milliseconds |
| **Performance** | Hypervisor overhead | Near bare-metal |
| **RAM** | Fixed reservation per VM | Shared, used on demand |
| **Density** | ~10 VMs/host | ~100+ containers/host |

### Dockerfile Instructions Reference

| Instruction | What it does |
|---|---|
| `FROM debian:bookworm` | Sets the base image |
| `RUN apt-get install ...` | Executes a command at build time, creating a layer |
| `COPY file /path/` | Copies files from the build context into the image |
| `WORKDIR /path` | Sets the working directory for subsequent instructions |
| `EXPOSE 9000` | Documents which port the container listens on (metadata only, does not publish) |
| `ENTRYPOINT ["script.sh"]` | The command that runs when the container starts |

### ENTRYPOINT: Exec-form vs Shell-form

- **Shell-form**: `ENTRYPOINT /usr/local/bin/script.sh`
  Docker runs `/bin/sh -c "..."` — the shell is PID 1, not your process. Signals from `docker stop` may not reach the daemon, leading to forced kills.

- **Exec-form**: `ENTRYPOINT ["/usr/local/bin/script.sh"]`
  Docker runs the script directly — no shell wrapper. The script (and after `exec`, the daemon) is PID 1 and receives signals correctly.

All Dockerfiles in this project use exec-form.

### Why `--no-install-recommends` and `rm -rf /var/lib/apt/lists/*`?

- `--no-install-recommends`: Prevents apt from pulling optional packages (documentation, GUI tools), keeping the image minimal.
- `rm -rf /var/lib/apt/lists/*`: Removes apt's package index cache. **Must be in the same `RUN` layer** as `apt-get update` — otherwise the cache files persist in the build layer and the cleanup has no effect on image size.

### Why not use `latest` tags?

`FROM debian:latest` is a floating pointer — it resolves to whatever Debian version is newest when the image is built. This breaks reproducibility: the same Dockerfile can produce different results on different days. All Dockerfiles use `FROM debian:bookworm` (a fixed version tag).

---

## 2. HTTPS & TLS

### Verifying HTTPS Access

Port 80 (HTTP) is never bound — `nginx.conf` only has `listen 443 ssl`. There is no port 80 server block. Testing:

```bash
# HTTP — must be refused
curl -I http://nakhalil.42.fr

# HTTPS — must succeed
curl -kI https://nakhalil.42.fr

# TLS 1.2 — must succeed
curl -k --tlsv1.2 --tls-max 1.2 https://nakhalil.42.fr -o /dev/null -w "%{http_code}\n"

# TLS 1.3 — must succeed
curl -k --tlsv1.3 https://nakhalil.42.fr -o /dev/null -w "%{http_code}\n"

# TLS 1.1 — must FAIL (not configured)
curl -k --tlsv1.1 --tls-max 1.1 https://nakhalil.42.fr
```

### What is TLS?

TLS (Transport Layer Security) encrypts all data between client and server. Without it, passwords, cookies, and content travel as plain text that anyone on the network can intercept.

**Handshake overview:**
1. Client says "I support TLS 1.2 and 1.3."
2. Server sends its certificate (public key) and picks a version/cipher.
3. Both sides derive a shared symmetric key via asymmetric cryptography.
4. All subsequent traffic is encrypted with that shared key.

### TLS 1.2 vs TLS 1.3

| | TLS 1.2 | TLS 1.3 |
|---|---|---|
| **Handshake** | 2 round trips | 1 round trip (faster) |
| **Cipher suites** | Includes some weak legacy options | All weak ciphers removed |
| **Security** | Secure with proper configuration | Secure by design |

`nginx.conf` enforces: `ssl_protocols TLSv1.2 TLSv1.3;` — TLS 1.0 and 1.1 are omitted because they have known vulnerabilities.

### SSL Certificate Generation

The certificate is generated at **container startup** (not build time) because `DOMAIN_NAME` is a runtime environment variable:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/nginx-selfsigned.key \
    -out /etc/ssl/certs/nginx-selfsigned.crt \
    -subj "/C=FR/ST=Paris/L=Paris/O=42/OU=Inception/CN=${DOMAIN_NAME}"
```

| Flag | Meaning |
|---|---|
| `-x509` | Self-signed certificate (not a CSR) |
| `-nodes` | No passphrase on the private key — NGINX reads it at boot without user input |
| `-days 365` | Valid for one year |
| `-newkey rsa:2048` | New 2048-bit RSA key pair |
| `CN=${DOMAIN_NAME}` | Common Name must match the domain |

The browser shows a "Not Secure" warning because the cert is self-signed (not issued by a trusted CA). The encryption itself is identical in strength.

### NGINX Architecture

NGINX is the **sole public entry point** and **TLS termination point**:
1. Receives HTTPS on port 443, decrypts TLS.
2. Routes to backends over the internal Docker network:
   - `*.php` → `wordpress:9000` via FastCGI
   - `/adminer` → `adminer:8080` via HTTP proxy
   - `/static/` → `static_site:3000` via HTTP proxy
   - Static assets → served directly from the `wordpress_vol` volume

---

## 3. WordPress & PHP-FPM

### Why PHP-FPM in a Separate Container?

NGINX cannot execute PHP — it only serves static files or proxies requests. WordPress is written entirely in PHP. PHP-FPM (FastCGI Process Manager) is the PHP engine that executes the code.

When NGINX receives a `.php` request:
1. Packages the request into the **FastCGI binary protocol**.
2. Sends it to `wordpress:9000` over TCP.
3. PHP-FPM executes the PHP script, queries MariaDB, returns HTML.
4. NGINX forwards the HTML to the browser.

```
Browser → NGINX (443) → PHP-FPM (9000) → MariaDB (3306)
                                        → Redis (6379)
```

### FastCGI vs CGI

- **CGI**: Forks a new process for every request. High overhead.
- **FastCGI**: PHP-FPM runs a persistent pool of workers. Requests are handed to long-running workers — no fork/kill per request, much faster.

### Why `listen = 9000` instead of a UNIX socket?

By default, PHP-FPM listens on `/run/php/php8.2-fpm.sock` — a UNIX domain socket (a file). UNIX sockets only work between processes sharing the same filesystem. NGINX is in a separate container with a separate filesystem, so TCP port 9000 is used instead.

### What is WP-CLI?

WP-CLI is the official command-line interface for WordPress. It lets `wp_setup.sh` fully automate installation without a browser:

```bash
wp core download          # download WordPress files
wp config create          # generate wp-config.php
wp core install           # configure site, create admin user
wp user create            # create second user
wp plugin install redis-cache --activate
wp redis enable
```

### WordPress Admin Username

The admin username is `nakhalil_master`. It contains no variant of "admin" in any form. The regular user is `student_user` with `author` role.

Verify: `docker exec wordpress wp user list --allow-root`

---

## 4. MariaDB

### Connecting to the Database

```bash
# As the WordPress user
docker exec -it mariadb mariadb -u nakhalil -p$(cat secrets/db_password.txt) wordpress_db

# Verify the database has data
SHOW TABLES;
SELECT ID, post_title FROM wp_posts LIMIT 5;

# Verify root is password-protected
docker exec -it mariadb mariadb -u root
# Expected: Access denied
```

### What is MariaDB?

MariaDB is a relational database management system (RDBMS) — a fully open-source fork of MySQL, wire-protocol compatible (same port 3306, same SQL syntax, same client tools). WordPress stores all posts, pages, users, settings, and plugin data in MariaDB.

### `bind-address = 0.0.0.0`

By default, MariaDB only accepts connections from `127.0.0.1`. Since WordPress runs in a separate container (different network namespace, different IP), `bind-address = 0.0.0.0` is required to accept connections from any IP on the Docker bridge. This is safe because port 3306 is only `expose`d (internal Docker network), not published to the host.

### `skip-name-resolve`

MariaDB normally performs a reverse DNS lookup on every incoming TCP connection. Container bridge IPs (like `172.20.0.5`) have no PTR records, causing timeouts on every connection. `skip-name-resolve` disables this, authenticating by IP address only.

---

## 5. Persistence & Volumes

### How Data Survives Container Removal

By default, writes inside a container go to its temporary writable layer — deleted when the container is removed. Persistent data requires **volumes**.

This project uses named volumes backed by host directories:
- `mariadb_vol` → `/home/nakhalil/data/mariadb` → mounted at `/var/lib/mysql`
- `wordpress_vol` → `/home/nakhalil/data/wordpress` → mounted at `/var/www/html`

Data is written directly to the host disk. Container removal and recreation doesn't affect it.

### Named Volumes with `driver_opts` (The Bind-Driver Pattern)

The project has two requirements that appear contradictory:
1. Use Docker named volumes (not plain bind mounts).
2. Store data at a specific host path (`/home/nakhalil/data/`).

Plain bind mounts (`- /home/nakhalil/data/mariadb:/var/lib/mysql`) are not named volumes — they don't appear in `docker volume ls`. Standard named volumes store data in `/var/lib/docker/volumes/` — not at the required path.

The solution — named volumes with `driver_opts`:

```yaml
volumes:
  mariadb_vol:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/nakhalil/data/mariadb
```

This creates a real Docker named volume (visible in `docker volume ls`, inspectable via `docker volume inspect`) while instructing the `local` driver to use a specific host path as storage. Both requirements are satisfied simultaneously.

### The Reboot Test

```bash
# 1. Make a visible change in the WordPress site
# 2. Reboot the machine
sudo reboot
# 3. After reboot
cd ~/Documents/inception && make up
# 4. Verify data is intact
docker exec mariadb mariadb -u nakhalil -p$(cat secrets/db_password.txt) \
  wordpress_db -e "SELECT post_title FROM wp_posts WHERE post_status='publish';"
```

---

## 6. Making Configuration Changes

When changing a service's port, update it in two places: where the service **listens** and where clients **connect** to it, then rebuild.

```bash
make re   # full rebuild (fclean + all)
```

### Port Change Reference

| Service | Where it listens | Where clients connect |
|---|---|---|
| **PHP-FPM** (9000→9001) | `wordpress/conf/www.conf`: `listen = 9001` | `nginx/conf/nginx.conf`: `fastcgi_pass wordpress:9001;` |
| **MariaDB** (3306→3307) | `mariadb/conf/50-server.cnf`: `port = 3307` | `wp_setup.sh`: `--dbhost="mariadb:3307"` + `docker-compose.yml`: `expose: ["3307"]` |
| **NGINX** (443→4443) | `nginx/conf/nginx.conf`: `listen 4443 ssl;` | `docker-compose.yml`: `ports: "4443:4443"` |
| **Redis** (6379→6380) | `redis/conf/redis.conf`: `port 6380` | `wp_setup.sh`: `WP_REDIS_PORT "6380"` |

---

## 7. Secrets vs Environment Variables

### Why Secrets for Passwords?

| | `.env` (environment variables) | Docker Secrets (`/run/secrets/`) |
|---|---|---|
| **Visibility** | Visible in `docker inspect <container>` | Not visible in `docker inspect` |
| **Storage** | Plain-text process environment | In-memory tmpfs (never touches disk) |
| **Logging risk** | Can appear in crash dumps | Never written to logs |
| **Git safety** | Easy to accidentally commit | Gitignored by design |

### What Goes Where

**`.env`** (non-sensitive, safe to track): `DOMAIN_NAME`, `MYSQL_USER`, `MYSQL_DATABASE`, `WP_ADMIN_USER`, `WP_ADMIN_EMAIL`, `WP_TITLE`, `FTP_USER`, `FTP_PASV_ADDRESS`.

**`secrets/`** (sensitive, gitignored): `db_password.txt`, `db_root_password.txt`, `wp_admin_password.txt`, `wp_user_password.txt`, `ftp_password.txt`.

### How Secrets Are Read in Scripts

```bash
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
```

Docker mounts each secret as a file from a tmpfs filesystem at `/run/secrets/<name>`. After `exec <daemon>` replaces the shell, the shell variable is gone. The secret is never stored in the environment.

---

## 8. Process Management & PID 1

### What is PID 1 in a Container?

PID 1 is the first process in the container's namespace. It has two critical responsibilities:

1. **Signal handling**: `docker stop` sends `SIGTERM` to PID 1 only. PID 1 must handle this to shut down gracefully. If it ignores `SIGTERM`, Docker waits 10 seconds then sends `SIGKILL` — a forced kill that can corrupt databases.

2. **Zombie reaping**: When child processes exit, they become zombies until their parent reads the exit code. PID 1 must reap orphaned zombies, otherwise they accumulate and exhaust the process table.

### How `exec` Makes the Daemon PID 1

Every entrypoint script ends with `exec`:

```bash
exec nginx -g "daemon off;"
exec php-fpm8.2 -F
exec mysqld_safe --user=mysql
exec vsftpd /etc/vsftpd.conf
```

`exec` **replaces** the shell process in memory. The shell ceases to exist; the daemon inherits PID 1.

**Without `exec`:**
```
PID 1: bash (the script)
PID 2: mysqld_safe (child)
```
`docker stop` → `SIGTERM` → bash → bash may not forward it → timeout → `SIGKILL` → potential data corruption.

**With `exec`:**
```
PID 1: mysqld_safe (bash replaced)
```
`docker stop` → `SIGTERM` → mysqld_safe → graceful shutdown.

### Why `daemon off;` and `-F`?

- `nginx -g "daemon off;"` — NGINX normally forks into the background (daemon mode) and the parent exits. In a container, if PID 1 exits, Docker stops the container. `daemon off` keeps NGINX in the foreground.
- `php-fpm8.2 -F` — Same: `-F` forces PHP-FPM to stay in the foreground instead of daemonizing.

### Patterns That Are Explicitly Avoided

| Pattern | Problem |
|---|---|
| `tail -f /dev/null` | A fake keep-alive — the process doing real work isn't PID 1 |
| `nginx & bash` | Daemon runs in background, shell is PID 1 — signals don't reach nginx |
| `sleep infinity` | Same fake keep-alive pattern |
| `while true; do sleep 1; done` | Infinite loop as entrypoint |

---

## 9. Makefile & Orchestration

### Target Reference

| Target | Action |
|---|---|
| `make all` | Create data dirs, build images, start containers |
| `make build` | `mkdir -p` data dirs + `docker compose build` |
| `make up` | `docker compose up -d` (images already built) |
| `make down` | `docker compose down` (volumes kept) |
| `make stop` | `docker compose stop` (pause without removing) |
| `make start` | `docker compose start` (resume) |
| `make status` | `docker compose ps` |
| `make logs` | `docker compose logs -f` |
| `make clean` | `down` + `docker system prune -f` |
| `make fclean` | `down -v --rmi all` + `rm -rf /home/nakhalil/data` |
| `make re` | `fclean` then `all` |

### Why `sudo mkdir -p` in the Build Target?

The host directories `/home/nakhalil/data/mariadb` and `/home/nakhalil/data/wordpress` must exist before Docker Compose creates the named volumes with `driver_opts`. If they don't exist, volume creation fails at `docker compose up`.

### `restart: always`

Docker automatically restarts a container if it exits with a non-zero code, or if the Docker daemon restarts (e.g., after a system reboot). Required for services to come back up automatically after the persistence reboot test.

### `depends_on` is Not a Readiness Check

```yaml
wordpress:
  depends_on: [mariadb, redis]
```

This tells Compose to start the MariaDB *container* before WordPress. It does **not** wait for MariaDB to be ready to accept connections. The `until mariadb-admin ping` loop in `wp_setup.sh` is the actual application-level readiness check.

---

## 10. Bonus Services

### Redis Cache

Redis is an in-memory key-value store used as a WordPress object cache. Instead of querying MariaDB for every page request, PHP-FPM checks Redis first. If the query result is cached, it's returned from RAM in microseconds instead of from disk.

The `redis-cache` WordPress plugin intercepts all database queries, caches results in Redis using the query as the key, and automatically invalidates entries when posts are updated.

```bash
docker exec redis redis-cli PING                      # PONG
docker exec redis redis-cli DBSIZE                    # active cache entries
docker exec wordpress wp redis status --allow-root    # Status: Connected
```

**`maxmemory-policy allkeys-lru`**: When Redis hits its memory cap, it evicts the Least Recently Used keys first — the correct eviction policy for a cache.

### FTP Server

vsftpd runs in its own container, mounting the same `wordpress_vol` volume as WordPress. This allows file management (themes, plugins, media uploads) via FTP without SSH access.

**Passive mode** is required in Docker because active mode requires the server to open connections back to the client — impossible from inside a private network. With passive mode, the client initiates all data connections on the published port range `21100–21110`.

**`chroot_local_user=YES`** jails the FTP user to `/var/www/html` — they cannot navigate outside this directory.

### Static Site

A plain HTML/CSS page served by Python's built-in HTTP server (`python3 -m http.server 3000`). No PHP, no framework. Demonstrates a non-PHP service running alongside the WordPress stack.

### Adminer

A complete database management GUI in a single PHP file, served by PHP's built-in server (`php -S 0.0.0.0:8080`). Proxied by NGINX at `/adminer`. Provides a web interface to inspect and query the MariaDB `wordpress_db` database.

### cAdvisor

Google's Container Advisor reads Linux cgroup and sysfs metrics to report real-time CPU, memory, network, and disk I/O for every running container. It monitors both individual containers and the host system.

Required bind mounts (all read-only):

| Mount | Purpose |
|---|---|
| `/:/rootfs:ro` | Host filesystem (disk usage) |
| `/var/run:/var/run:ro` | Runtime state |
| `/sys:/sys:ro` | Kernel cgroup metrics |
| `/var/lib/docker:/var/lib/docker:ro` | Docker container metadata |
| `/dev/disk:/dev/disk:ro` | Disk device info |

Access: `http://localhost:8080`

---

## 11. Critical Requirements at a Glance

| Requirement | Implementation |
|---|---|
| No `network_mode: host` | Custom bridge network `srcs_inception_net` used throughout |
| No `--link` or `links:` | Container-name DNS resolution via Docker's embedded DNS (`127.0.0.11`) |
| `networks:` must be present | `inception_net: driver: bridge` defined and attached to all services |
| No fake keep-alives (`tail -f`, `sleep infinity`) | Every entrypoint ends with `exec <daemon>` in foreground |
| No passwords in Dockerfiles | All passwords read at runtime from `/run/secrets/` |
| No passwords in Git | `secrets/` is gitignored; `.env` contains only non-sensitive config |
| One service per container | 8 containers, each running exactly one service |
| Base image: penultimate Debian/Alpine | `FROM debian:bookworm` (Debian 12) in all Dockerfiles |
| Image name = service name | `image: nginx:inception`, `image: mariadb:inception`, etc. |
| Containers restart on crash | `restart: always` on every service |
| Data at `/home/nakhalil/data/` | Named volumes with `driver: local` + `driver_opts` bind device |
| NGINX is the only HTTPS entry point | Only NGINX has `ports: "443:443"`; all others use `expose:` |
| No `latest` tags | All `FROM` instructions use pinned version tags |
| No `tail -f` or background loops in entrypoints | All entrypoints are linear setup scripts ending with `exec` |
