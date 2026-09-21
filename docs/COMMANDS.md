# Inception — Command Reference

Operational commands for managing, inspecting, and verifying the running infrastructure.

> **Credential reference** (from `srcs/.env` and `secrets/`):
> - Domain: `nakhalil.42.fr`
> - DB user / DB name: `nakhalil` / `wordpress_db`
> - WP admin / regular user: `nakhalil_master` / `student_user`
> - FTP user: `ftpuser`

---

## 1. Project Lifecycle

```bash
make all        # build images + create/start all containers (first run)
make up         # start already-built containers
make down       # stop & remove containers (data volumes preserved)
make stop       # pause running containers without removing
make start      # resume paused containers
make status     # show container status (docker compose ps)
make logs       # follow all container logs in real-time
make clean      # down + prune stopped containers and dangling images
make fclean     # nuclear: down, remove all images/volumes, delete /home/nakhalil/data
make re         # fclean + all (full rebuild from scratch)
```

---

## 2. Container Status

```bash
# Status of all services
docker compose -f srcs/docker-compose.yml ps

# All containers including stopped/crashed ones
docker ps -a

# Filter by service name
docker ps | grep nginx
docker ps | grep mariadb
docker ps | grep wordpress
```

All 8 services should show `Up`: `nginx`, `wordpress`, `mariadb`, `redis`, `adminer`, `static_site`, `ftp`, `cadvisor`.

---

## 3. Images

```bash
# List built images (each must be named <service>:inception)
docker images
```

Expected:
```
nginx:inception
wordpress:inception
mariadb:inception
redis:inception
adminer:inception
static_site:inception
ftp:inception
cadvisor:inception
```

---

## 4. Network Inspection

```bash
# List all networks — must include srcs_inception_net
docker network ls

# Inspect: shows all connected containers and their internal IPs
docker network inspect srcs_inception_net

# Test DNS resolution from inside a container
docker exec wordpress getent hosts mariadb
# Expected: 172.20.0.X  mariadb

# Verify MariaDB is NOT reachable from the host (uses expose:, not ports:)
nc -zv 127.0.0.1 3306
# Expected: Connection refused

# Verify NGINX IS reachable from the host (uses ports: 443:443)
nc -zv 127.0.0.1 443
# Expected: Connection succeeded
```

---

## 5. Volume Inspection

```bash
# List volumes
docker volume ls
# Must include: srcs_mariadb_vol, srcs_wordpress_vol

# Inspect — verify device path contains /home/nakhalil/data
docker volume inspect srcs_mariadb_vol
docker volume inspect srcs_wordpress_vol
```

Expected in inspect output:
```json
"Options": {
    "device": "/home/nakhalil/data/mariadb",
    "o": "bind",
    "type": "none"
}
```

Verify data on disk:
```bash
ls /home/nakhalil/data/mariadb     # mysql/, wordpress_db/, ibdata1, etc.
ls /home/nakhalil/data/wordpress   # wp-config.php, wp-content/, index.php, etc.
```

---

## 6. TLS Verification

```bash
# HTTP must be refused (no listen 80 in nginx.conf)
curl -I http://nakhalil.42.fr

# HTTPS must succeed
curl -kI https://nakhalil.42.fr

# TLS 1.2 — must succeed
curl -k --tlsv1.2 --tls-max 1.2 https://nakhalil.42.fr -o /dev/null -w "%{http_code}\n"

# TLS 1.3 — must succeed
curl -k --tlsv1.3 https://nakhalil.42.fr -o /dev/null -w "%{http_code}\n"

# TLS 1.1 — must fail (not configured)
curl -k --tlsv1.1 --tls-max 1.1 https://nakhalil.42.fr

# Inspect the certificate
echo | openssl s_client -connect nakhalil.42.fr:443 2>/dev/null | openssl x509 -noout -text | grep CN

# From inside the NGINX container
docker exec nginx nginx -t
docker exec nginx cat /etc/nginx/conf.d/default.conf
docker exec nginx openssl x509 -in /etc/ssl/certs/nginx-selfsigned.crt -noout -subject
```

---

## 7. MariaDB

```bash
# Log in as the WordPress database user
docker exec -it mariadb mariadb -u nakhalil -p$(cat secrets/db_password.txt) wordpress_db

# Verify tables exist (DB is not empty)
SHOW TABLES;
SELECT ID, post_title FROM wp_posts LIMIT 5;

# One-liner (no interactive shell)
docker exec mariadb mariadb -u nakhalil -p$(cat secrets/db_password.txt) \
  wordpress_db -e "SHOW TABLES;"

# Verify root login is password-protected
docker exec -it mariadb mariadb -u root
# Expected: ERROR 1045 Access denied

# List all database users
docker exec mariadb mariadb -u root -p$(cat secrets/db_root_password.txt) \
  -e "SELECT user, host FROM mysql.user;"
```

---

## 8. WordPress

```bash
# List users — must show nakhalil_master (admin) and student_user (author)
docker exec wordpress wp user list --allow-root

# Inspect the admin account
docker exec wordpress wp user get nakhalil_master --allow-root

# Confirm no NGINX binary in the WordPress container
docker exec wordpress which nginx
# Expected: no output (exit code 1)

# View wp-config.php database and Redis settings
docker exec wordpress wp config get --allow-root | grep -E "DB_|REDIS"

# List installed plugins
docker exec wordpress wp plugin list --allow-root
```

---

## 9. Redis

```bash
# Basic connectivity check
docker exec redis redis-cli PING
# Expected: PONG

# Check cached keys (non-zero after first page load)
docker exec redis redis-cli DBSIZE

# Detailed keyspace info
docker exec redis redis-cli INFO keyspace

# Verify connection from WordPress side
docker exec wordpress wp redis status --allow-root
# Expected: Status: Connected

# Flush the cache manually
docker exec wordpress wp redis flush --allow-root
```

---

## 10. Bonus Services

### Adminer
```bash
docker ps | grep adminer
docker exec adminer which nginx   # should return nothing
# Browser: https://nakhalil.42.fr/adminer
# Server=mariadb, User=nakhalil, Password=(secrets/db_password.txt), DB=wordpress_db
```

### Static Site
```bash
docker exec static_site which php   # should return nothing
# Browser: https://nakhalil.42.fr/static/
```

### FTP
```bash
ftp localhost 21
# Name: ftpuser
# Password: (contents of secrets/ftp_password.txt)
ftp> ls       # lists /var/www/html (WordPress files)
ftp> cd ..    # should fail or stay in place (chroot jail)
ftp> quit
```

### cAdvisor
```bash
docker ps | grep cadvisor
# Browser: http://localhost:8080
# Real-time CPU, memory, and network graphs for all containers
```

---

## 11. Entering Containers

```bash
docker exec -it nginx bash
docker exec -it wordpress bash
docker exec -it mariadb bash
docker exec -it redis bash
docker exec -it adminer bash
docker exec -it ftp bash
docker exec -it static_site bash
docker exec -it cadvisor sh    # no bash available
```

---

## 12. Logs

```bash
docker logs -f nginx        # access log, TLS errors, proxy errors
docker logs -f wordpress    # wp_setup.sh output, PHP-FPM startup
docker logs -f mariadb      # init_db.sh output, SQL errors
docker logs -f redis        # startup, connection events
docker logs -f ftp          # vsftpd connection log
```

---

## 13. Persistence Verification

```bash
# 1. Make a visible change (publish a post, add a comment)

# 2. Reboot
sudo reboot

# 3. After reboot, start the project
cd ~/Documents/inception && make up

# 4. Verify data survived
docker exec mariadb mariadb -u nakhalil -p$(cat secrets/db_password.txt) \
  wordpress_db -e "SELECT post_title FROM wp_posts WHERE post_status='publish';"

# 5. Open https://nakhalil.42.fr — site loads, all changes intact
```

---

## 14. Live Resource Monitoring

```bash
# Real-time CPU/Memory/IO per container (terminal)
docker stats

# Web dashboard with historical graphs
# http://localhost:8080  (cAdvisor)
```

---

## 15. Full Environment Reset

```bash
# Complete teardown — removes all containers, images, volumes, and host data
docker stop $(docker ps -qa)
docker rm $(docker ps -qa)
docker rmi -f $(docker images -qa)
docker volume rm $(docker volume ls -q)
docker network rm $(docker network ls -q) 2>/dev/null
sudo rm -rf /home/nakhalil/data/*

# Makefile equivalent (same result in one command):
make fclean

# Rebuild everything from scratch:
make all
```

> ⚠️ This permanently deletes all WordPress and MariaDB data. Use only for full environment resets.
