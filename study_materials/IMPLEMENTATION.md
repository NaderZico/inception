# Inception — Implementation Reference

Per-service deep dive: every Dockerfile, config file, and entrypoint script explained line-by-line. This is the "how it was built" companion to `EVALUATION_QA.md` (the "why") and `ARCHITECTURE.md` (the "what connects to what").

---

## Table of Contents
1. [MariaDB](#1-mariadb)
2. [WordPress + PHP-FPM](#2-wordpress--php-fpm)
3. [NGINX](#3-nginx)
4. [Redis](#4-redis)
5. [Adminer](#5-adminer)
6. [Static Site](#6-static-site)
7. [FTP Server (vsftpd)](#7-ftp-server-vsftpd)
8. [cAdvisor](#8-cadvisor)
9. [Cross-Cutting Concepts](#9-cross-cutting-concepts)

---

## 1. MariaDB

**Location:** `srcs/requirements/mariadb/`

### Dockerfile

```dockerfile
FROM debian:bookworm
RUN apt-get update && \
    apt-get install -y --no-install-recommends mariadb-server mariadb-client && \
    rm -rf /var/lib/apt/lists/*
COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf
COPY tools/init_db.sh /usr/local/bin/init_db.sh
RUN chmod +x /usr/local/bin/init_db.sh
EXPOSE 3306
ENTRYPOINT ["/usr/local/bin/init_db.sh"]
```

- `mariadb-client` is needed because `mariadb-admin ping` is used by `wp_setup.sh` to check if MariaDB is ready.
- `--no-install-recommends` + `rm -rf /var/lib/apt/lists/*` minimize image size.

### `50-server.cnf`

```ini
[mysqld]
bind-address    = 0.0.0.0
skip-name-resolve
character-set-server  = utf8mb4
collation-server      = utf8mb4_general_ci
```

| Setting | Why |
|---|---|
| `bind-address = 0.0.0.0` | Allows connections from any IP on the Docker network (not just localhost). Without this, WordPress in a separate container can't reach MariaDB. |
| `skip-name-resolve` | Disables reverse DNS lookups on every connection. Without this, MariaDB tries to resolve the connecting container's IP to a hostname — Docker bridge IPs have no PTR records, causing connection timeouts and `Host not allowed` errors. |
| `utf8mb4` | True 4-byte UTF-8, supporting emoji and all Unicode. MySQL's `utf8` is historically 3-byte and doesn't support the full Unicode range. |

### `init_db.sh` — Step by Step

```bash
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
MYSQL_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
```
Reads passwords from Docker secrets (mounted at `/run/secrets/`) — never from environment variables.

```bash
mkdir -p /run/mysqld /var/lib/mysql /var/log/mysql
chown -R mysql:mysql /run/mysqld /var/lib/mysql /var/log/mysql
```
MariaDB's daemon expects to own these directories and runs as the `mysql` user, not root.

```bash
if [ ! -d "/var/lib/mysql/mysql" ]; then
```
**Idempotency guard**: if the volume already has data (container rebuilt but volume preserved), skip initialization entirely. Without this, every restart would wipe the database.

**First-run initialization sequence:**
1. `mariadb-install-db` — creates the system tables and raw data directory structure.
2. `mysqld_safe --skip-networking &` — starts the daemon temporarily in the background with networking disabled so no external connections arrive during initialization.
3. `mariadb-admin ping` loop — waits for the daemon to become responsive.
4. SQL statements: creates the database, creates the WordPress user with the correct grants, sets the root password.
5. Shuts down the temporary daemon with `mysqladmin shutdown`.
6. `exec mysqld_safe --user=mysql` — starts the permanent daemon as PID 1.

**Why `exec`?** The `exec` shell builtin *replaces* the current shell process in memory. Without it, the shell script stays as PID 1 and `mysqld_safe` is a child (PID 2). `docker stop` sends `SIGTERM` to PID 1 only — if that's bash, the signal may not reach the database, resulting in a forced `SIGKILL` after 10 seconds and potential data corruption.

---

## 2. WordPress + PHP-FPM

**Location:** `srcs/requirements/wordpress/`

### Dockerfile

```dockerfile
FROM debian:bookworm
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        php8.2-fpm php8.2-mysql php8.2-curl php8.2-gd \
        php8.2-mbstring php8.2-xml php8.2-zip php-redis \
        mariadb-client curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp
COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY tools/wp_setup.sh /usr/local/bin/wp_setup.sh
RUN chmod +x /usr/local/bin/wp_setup.sh
WORKDIR /var/www/html
EXPOSE 9000
ENTRYPOINT ["/usr/local/bin/wp_setup.sh"]
```

**PHP extensions:**

| Extension | Why |
|---|---|
| `php8.2-fpm` | The FastCGI Process Manager — the PHP engine itself |
| `php8.2-mysql` | WordPress needs this to connect to MariaDB via MySQLi/PDO |
| `php8.2-curl` | WordPress uses cURL for plugin downloads, pingbacks, API calls |
| `php8.2-gd` | Image manipulation: thumbnails, resizing uploaded images |
| `php8.2-mbstring` | Multi-byte string handling for non-ASCII characters |
| `php8.2-xml` | XML parsing used by many WordPress plugins and the REST API |
| `php8.2-zip` | Required to install/update plugins and themes as zip files |
| `php-redis` | PHP extension that lets WordPress talk to the Redis server |
| `mariadb-client` | Provides `mariadb-admin` for the readiness check loop in `wp_setup.sh` |

**WP-CLI** is downloaded as a `.phar` (PHP archive — a self-contained PHP script). It enables full WordPress management from the command line, which is essential during container startup when no browser is available.

### `www.conf` — PHP-FPM Pool Config

```ini
[www]
user  = www-data
group = www-data
listen = 9000
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children   = 25
pm.start_servers  = 5
pm.min_spare_servers = 1
pm.max_spare_servers = 10
clear_env = no
```

| Setting | Why |
|---|---|
| `listen = 9000` | PHP-FPM listens on a TCP port instead of the default UNIX socket (`/run/php/php8.2-fpm.sock`). UNIX sockets are files — they can't cross container boundaries. TCP port 9000 is reachable over the Docker bridge network. |
| `clear_env = no` | Without this, PHP-FPM strips all environment variables from worker processes. WordPress setup needs `DOMAIN_NAME`, `MYSQL_USER`, `MYSQL_DATABASE`, etc. from the `.env` file. |
| `pm = dynamic` | PHP-FPM manages a pool of worker processes dynamically. Workers are created and destroyed based on load, within the bounds set by `pm.*` values. |
| `pm.max_children = 25` | Maximum concurrent PHP requests |
| `pm.start_servers = 5` | Workers spawned at startup |
| `pm.min/max_spare_servers` | Idle workers kept alive for fast response to bursts |

### `wp_setup.sh` — Step by Step

```bash
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
WP_ADMIN_PASSWORD=$(cat /run/secrets/wp_admin_password)
WP_USER_PASSWORD=$(cat /run/secrets/wp_user_password)
```
Reads all passwords from Docker secrets.

```bash
until mariadb-admin -h"mariadb" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" --skip-ssl ping >/dev/null 2>&1; do
    sleep 2
done
```
**Application-level readiness check**: `depends_on: [mariadb]` in `docker-compose.yml` only waits for the MariaDB *container* to start, not for MariaDB *itself* to accept connections. Without this loop, `wp config create` would fail immediately with a connection error.

```bash
if [ ! -f /var/www/html/wp-config.php ]; then
```
**Idempotency guard**: only runs the full installation on first boot. On subsequent starts, `wordpress_vol` already has the configured WordPress installation.

**WP-CLI commands in sequence:**
1. `wp core download` — downloads WordPress core files into `/var/www/html`
2. `wp config create` — generates `wp-config.php` with database credentials
3. `wp core install` — runs the installer (creates DB tables, sets admin user, configures URL)
4. `wp user create` — creates the second user (`student_user` with `author` role)
5. `wp plugin install redis-cache --activate` — installs the Redis Object Cache plugin
6. `wp config set WP_REDIS_HOST "redis"` — tells WordPress where Redis is
7. `wp config set WP_REDIS_PORT "6379"` — Redis port
8. `wp config set WP_CACHE true` — enables object caching
9. `wp redis enable` — activates the Redis cache backend

```bash
exec php-fpm8.2 -F
```
`-F` forces foreground mode. Without it, PHP-FPM would daemonize (fork and exit the parent), causing Docker to think the container stopped. `exec` replaces the shell with PHP-FPM as PID 1.

**Admin username (`nakhalil_master`):** The subject explicitly forbids usernames that contain `admin` or `Admin` in any form.

---

## 3. NGINX

**Location:** `srcs/requirements/nginx/`

### Dockerfile

```dockerfile
FROM debian:bookworm
RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx openssl && \
    rm -rf /var/lib/apt/lists/*
COPY conf/nginx.conf /etc/nginx/conf.d/default.conf
COPY tools/nginx_setup.sh /usr/local/bin/nginx_setup.sh
RUN chmod +x /usr/local/bin/nginx_setup.sh
EXPOSE 443
ENTRYPOINT ["/usr/local/bin/nginx_setup.sh"]
```

`openssl` is installed here (not pre-generated into the image) because the TLS certificate is created at **container startup** so it can embed the runtime `DOMAIN_NAME` environment variable.

### `nginx_setup.sh`

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/nginx-selfsigned.key \
    -out /etc/ssl/certs/nginx-selfsigned.crt \
    -subj "/C=FR/ST=Paris/L=Paris/O=42/OU=Inception/CN=${DOMAIN_NAME}"

sed -i "s/DOMAIN_NAME_PLACEHOLDER/${DOMAIN_NAME}/g" /etc/nginx/conf.d/default.conf

exec nginx -g "daemon off;"
```

| Flag | Meaning |
|---|---|
| `-x509` | Output a self-signed certificate (not a Certificate Signing Request) |
| `-nodes` | No passphrase on the private key (NGINX reads it automatically at startup) |
| `-newkey rsa:2048` | Generate a new 2048-bit RSA key pair |
| `CN=${DOMAIN_NAME}` | The Common Name must match the domain the browser connects to |
| `daemon off` | Keeps NGINX in the foreground so it runs as PID 1 |

The `sed` replaces the `DOMAIN_NAME_PLACEHOLDER` literal in `nginx.conf` with the actual domain name at runtime.

### `nginx.conf` — Annotated

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name DOMAIN_NAME_PLACEHOLDER localhost;

    ssl_certificate     /etc/ssl/certs/nginx-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
```
Only port 443 with TLS 1.2/1.3. There is **no `listen 80` block** — HTTP is completely disabled. `ssl_prefer_server_ciphers off` lets the client choose the cipher, which is the modern best practice for TLS 1.3.

```nginx
    root /var/www/html;
    index index.php;

    location ^~ /static/ {
        proxy_pass http://static_site:3000/;
    }

    location ^~ /adminer {
        proxy_pass http://adminer:8080;
    }
```
`^~` (prefix) locations take priority over regex. These two are matched first, before the PHP location below. Requests to `/static/` and `/adminer` are proxied to their containers via Docker DNS.

```nginx
    location / {
        try_files $uri $uri/ /index.php?$args;
    }
```
Standard WordPress permalink rule: try the exact file, then the directory, then fall back to `index.php` with query args (for pretty URLs like `/blog/my-post/`).

```nginx
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass wordpress:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
```
Any `.php` request is forwarded to the WordPress container via the FastCGI protocol on port 9000. `SCRIPT_FILENAME` tells PHP-FPM the absolute path of the script to execute. `fastcgi_params` sets standard CGI variables (REQUEST_METHOD, QUERY_STRING, etc.).

---

## 4. Redis

**Location:** `srcs/requirements/bonus/redis/`

### Dockerfile

```dockerfile
FROM debian:bookworm
RUN apt-get update && \
    apt-get install -y --no-install-recommends redis-server && \
    rm -rf /var/lib/apt/lists/*
COPY conf/redis.conf /etc/redis/redis.conf
EXPOSE 6379
ENTRYPOINT ["redis-server", "/etc/redis/redis.conf", "--daemonize", "no"]
```

`--daemonize no` is passed as an argument to override any `daemonize yes` that might appear in the config. Redis must run in the foreground.

### `redis.conf`

```
protected-mode no
port 6379
maxmemory 256mb
maxmemory-policy allkeys-lru
```

| Setting | Why |
|---|---|
| `protected-mode no` | Redis's protected mode requires either a password or localhost binding. Since we're on a private Docker network (no public exposure), this is safe to disable. Redis is only reachable within `inception_net`. |
| `maxmemory 256mb` | Caps Redis memory so it can't grow unbounded. |
| `maxmemory-policy allkeys-lru` | When memory is full, evict the **L**east **R**ecently **U**sed keys first. Correct policy for a cache — old, unused data is removed automatically. |

### How WordPress uses Redis

In `wp_setup.sh`, these commands configure the Redis Object Cache plugin:
```bash
wp plugin install redis-cache --activate
wp config set WP_REDIS_HOST "redis"
wp config set WP_REDIS_PORT "6379" --raw
wp config set WP_CACHE true --raw
wp redis enable
```

The plugin intercepts WordPress's database queries, stores the results in Redis RAM using the query as a cache key, and serves subsequent identical queries from memory instead of hitting MariaDB. Cache is automatically invalidated when posts are saved or updated.

---

## 5. Adminer

**Location:** `srcs/requirements/bonus/adminer/`

### Dockerfile

```dockerfile
FROM debian:bookworm
RUN apt-get update && \
    apt-get install -y --no-install-recommends php php-mysql wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*
RUN mkdir -p /var/www/adminer
WORKDIR /var/www/adminer
RUN wget -O index.php https://github.com/vrana/adminer/releases/download/v4.8.1/adminer-4.8.1.php
EXPOSE 8080
ENTRYPOINT ["php", "-S", "0.0.0.0:8080", "-t", "/var/www/adminer"]
```

Adminer is a complete database management UI in a **single PHP file**. `php -S 0.0.0.0:8080` is PHP's built-in development web server — no NGINX, no Apache, no configuration needed.

**Access:** `https://nakhalil.42.fr/adminer` (NGINX proxies `/adminer` → `adminer:8080`)

**Login credentials:**
- Server: `mariadb`
- Username: `nakhalil` (from `.env`)
- Password: contents of `secrets/db_password.txt`
- Database: `wordpress_db`

---

## 6. Static Site

**Location:** `srcs/requirements/bonus/static_site/`

### Dockerfile

```dockerfile
FROM debian:bookworm
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 && \
    rm -rf /var/lib/apt/lists/*
COPY src /var/www/html
WORKDIR /var/www/html
EXPOSE 3000
ENTRYPOINT ["python3", "-m", "http.server", "3000"]
```

A plain HTML/CSS page served by Python's built-in HTTP server. The subject requires a static site in **any language except PHP** — Python is used as the server runtime (not for content). No framework, no PHP, no configuration.

`python3 -m http.server 3000` is a zero-config file server that serves everything in the working directory over HTTP.

**Access:** `https://nakhalil.42.fr/static/` (NGINX proxies `/static/` → `static_site:3000`)

---

## 7. FTP Server (vsftpd)

**Location:** `srcs/requirements/bonus/ftp/`

### Dockerfile

```dockerfile
FROM debian:bookworm
RUN apt-get update && \
    apt-get install -y vsftpd && \
    rm -rf /var/lib/apt/lists/*
COPY conf/vsftpd.conf /etc/vsftpd.conf
COPY tools/ftp_setup.sh /usr/local/bin/ftp_setup.sh
RUN chmod +x /usr/local/bin/ftp_setup.sh
EXPOSE 21 21100-21110
ENTRYPOINT ["/usr/local/bin/ftp_setup.sh"]
```

### Active vs Passive FTP — Why Passive?

FTP has two data transfer modes:
- **Active mode**: The *server* opens a connection back to the client on a random port. This fails in Docker because the FTP container is inside a private network and can't initiate connections to the client.
- **Passive mode**: The *client* opens all connections to the server on a pre-agreed port range. This works in Docker because the client initiates everything.

Passive ports `21100–21110` are published in `docker-compose.yml` (`ports: ["21100-21110:21100-21110"]`) so Docker NAT forwards them to the container.

### `vsftpd.conf`

```ini
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=21100
pasv_max_port=21110
pasv_address=PASV_ADDR_PLACEHOLDER
```

| Setting | Why |
|---|---|
| `chroot_local_user=YES` | Jails the FTP user to their home directory (`/var/www/html`). They can't navigate to `/etc`, `/bin`, or anywhere else on the container filesystem. |
| `allow_writeable_chroot=YES` | Required when the chroot jail directory itself is writable (which `/var/www/html` must be for file uploads). |
| `pasv_address` | The IP clients use to connect for passive data transfers. Replaced at runtime from `FTP_PASV_ADDRESS` in `.env` (defaults to `127.0.0.1` for local VM). |

### `ftp_setup.sh`

```bash
FTP_PASSWORD=$(cat /run/secrets/ftp_password)

if ! id -u "$FTP_USER" &>/dev/null; then
    useradd -m -d /var/www/html -s /bin/bash "$FTP_USER"
    echo "$FTP_USER:$FTP_PASSWORD" | chpasswd
    usermod -aG www-data "$FTP_USER"
fi

chown -R $FTP_USER:www-data /var/www/html

PASV_ADDR="${FTP_PASV_ADDRESS:-127.0.0.1}"
sed -i "s/PASV_ADDR_PLACEHOLDER/${PASV_ADDR}/g" /etc/vsftpd.conf

exec vsftpd /etc/vsftpd.conf
```

The FTP user is added to the `www-data` group so they can read/write files owned by `www-data` (all WordPress files). This avoids permission conflicts without giving the FTP user root access.

**Test:**
```bash
ftp localhost 21
# Name: ftpuser
# Password: (from secrets/ftp_password.txt)
ftp> ls    # lists /var/www/html — WordPress files
ftp> quit
```

---

## 8. cAdvisor

**Location:** `srcs/requirements/bonus/cadvisor/`

### Dockerfile

```dockerfile
FROM debian:bookworm
RUN apt-get update && \
    apt-get install -y --no-install-recommends wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*
RUN wget -O /usr/local/bin/cadvisor \
    https://github.com/google/cadvisor/releases/download/v0.49.1/cadvisor-v0.49.1-linux-amd64 && \
    chmod +x /usr/local/bin/cadvisor
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/cadvisor", "--port=8080"]
```

cAdvisor (Container Advisor) is a Google tool that reads Linux kernel resource metrics from cgroups and sysfs to report per-container CPU, memory, network, and disk I/O — in real time.

### Why the bind mounts?

```yaml
volumes:
  - /:/rootfs:ro                         # Host filesystem (disk usage)
  - /var/run:/var/run:ro                 # Running process info
  - /sys:/sys:ro                         # Kernel cgroup metrics
  - /var/lib/docker/:/var/lib/docker:ro  # Docker container metadata
  - /dev/disk/:/dev/disk:ro              # Disk device info
```

cAdvisor needs access to the host's cgroup hierarchy and sysfs to collect container metrics. All mounts are `:ro` (read-only) — cAdvisor observes, it doesn't modify.

**Access:** `http://localhost:8080` (published directly to host, not proxied through NGINX)

---

## 9. Cross-Cutting Concepts

### PID 1 and `exec`

Every entrypoint script ends with `exec <daemon>`. The `exec` shell builtin **replaces** the current shell process in memory — the shell ceases to exist and the daemon inherits PID 1.

**Without `exec`:**
```
PID 1: bash (the script)
PID 2: mysqld_safe (child process)
```
`docker stop` → `SIGTERM` → PID 1 (bash) → bash may not forward it → 10-second timeout → `SIGKILL` → potential data corruption.

**With `exec`:**
```
PID 1: mysqld_safe (bash was replaced)
```
`docker stop` → `SIGTERM` → PID 1 (mysqld_safe) → graceful shutdown.

---

### `depends_on` is NOT a readiness check

```yaml
wordpress:
  depends_on: [mariadb, redis]
```

This makes Docker Compose start the MariaDB *container* before WordPress. It does **not** wait for MariaDB to be ready to accept connections. That's why `wp_setup.sh` has the `until mariadb-admin ping` loop — a real application-level readiness check that waits for the database to actually respond before proceeding.

---

### `set -e` in all scripts

Every shell script starts with `set -e`. This causes the script to exit immediately on any failed command. Without it, a failed `wp core download` would be silently ignored and the script would continue running broken subsequent commands.

---

### No `latest` tag

Every `FROM` uses `debian:bookworm`, not `debian:latest`. `latest` is a floating tag — it changes when a new major version is released, making builds non-reproducible. A pinned tag ensures the same base OS every time the image is built.

---

### No passwords in Dockerfiles

The subject forbids passwords in Dockerfiles (they end up in image layers and `docker inspect` output). All passwords are read at runtime from `/run/secrets/`. Dockerfiles only install software and copy configuration templates with placeholders.
