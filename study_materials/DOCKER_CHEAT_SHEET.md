# Inception — Docker & System Commands Cheat Sheet

All commands use the real names from this project. Credentials come from `srcs/.env` and `secrets/`.

> **Quick credential reference** (from `.env`):
> - Domain: `nakhalil.42.fr`
> - DB user: `nakhalil` / DB name: `wordpress_db`
> - WP admin: `nakhalil_master` / WP regular user: `student_user`
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

## 2. Verifying Containers Are Running

```bash
# Quick status overview
docker compose -f srcs/docker-compose.yml ps

# All containers (including stopped/crashed)
docker ps -a

# Check a specific container
docker ps | grep nginx
docker ps | grep mariadb
docker ps | grep wordpress
```

Expected: all 8 containers show `Up` status: `nginx`, `wordpress`, `mariadb`, `redis`, `adminer`, `static_site`, `ftp`, `cadvisor`.

---

## 3. Verifying Images Are Named Correctly

```bash
docker images
```

Expected (subject requires image name = service name):
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

## 4. Verifying Networks

```bash
# List all networks — must show srcs_inception_net
docker network ls

# Inspect — shows all connected containers and their internal IPs
docker network inspect srcs_inception_net

# Test DNS from inside a container (prove containers resolve each other by name)
docker exec wordpress getent hosts mariadb
# Expected: 172.20.0.X  mariadb

# Prove MariaDB is NOT reachable from the host (only expose:, not ports:)
nc -zv 127.0.0.1 3306
# Expected: Connection refused

# Prove NGINX IS reachable from the host (ports: 443:443)
nc -zv 127.0.0.1 443
# Expected: Connection succeeded
```

---

## 5. Verifying Volumes

```bash
# List volumes — must show srcs_mariadb_vol and srcs_wordpress_vol
docker volume ls

# Inspect each volume — look for /home/nakhalil/data in "Options"."device"
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

Also verify data is on disk:
```bash
ls /home/nakhalil/data/mariadb    # should show mysql/, wordpress_db/, etc.
ls /home/nakhalil/data/wordpress  # should show wp-config.php, wp-content/, etc.
```

---

## 6. Checking TLS (NGINX)

```bash
# HTTP must be REFUSED (no listen 80 in nginx.conf)
curl -I http://nakhalil.42.fr
# Expected: curl: (7) Failed to connect ... port 80: Connection refused

# HTTPS must work
curl -kI https://nakhalil.42.fr
# Expected: HTTP/2 200

# TLS 1.2 must work
curl -k --tlsv1.2 --tls-max 1.2 https://nakhalil.42.fr -o /dev/null -w "%{http_code}\n"
# Expected: 200

# TLS 1.3 must work
curl -k --tlsv1.3 https://nakhalil.42.fr -o /dev/null -w "%{http_code}\n"
# Expected: 200

# TLS 1.1 must FAIL
curl -k --tlsv1.1 --tls-max 1.1 https://nakhalil.42.fr
# Expected: handshake failure / protocol error

# Inspect the certificate (check CN and protocol)
echo | openssl s_client -connect nakhalil.42.fr:443 2>/dev/null | openssl x509 -noout -text | grep -E "Subject:|Protocol"
# Look for: Subject: ... CN=nakhalil.42.fr

# From inside the NGINX container
docker exec nginx nginx -t                                          # test config syntax
docker exec nginx cat /etc/nginx/conf.d/default.conf               # verify domain was substituted
docker exec nginx openssl x509 -in /etc/ssl/certs/nginx-selfsigned.crt -noout -text | grep CN
```

---

## 7. Verifying MariaDB

```bash
# Log in as the WordPress user
docker exec -it mariadb mariadb -u nakhalil -p$(cat secrets/db_password.txt) wordpress_db

# Once inside, verify the DB is not empty:
SHOW TABLES;
# Expected: wp_posts, wp_users, wp_options, wp_comments, etc.

SELECT ID, post_title FROM wp_posts LIMIT 5;

# Or one-liner (no interactive shell):
docker exec mariadb mariadb -u nakhalil -p$(cat secrets/db_password.txt) wordpress_db -e "SHOW TABLES;"

# Verify root cannot login without password (security check):
docker exec -it mariadb mariadb -u root
# Expected: ERROR 1045 (28000): Access denied

# Verify the nakhalil user exists:
docker exec mariadb mariadb -u root -p$(cat secrets/db_root_password.txt) \
  -e "SELECT user, host FROM mysql.user;"
```

---

## 8. Verifying WordPress & Users

```bash
# List all users — must show exactly 2: nakhalil_master (admin) and student_user (author)
docker exec wordpress wp user list --allow-root

# Verify admin username has no "admin" in it
docker exec wordpress wp user get nakhalil_master --allow-root | grep roles
# Expected: administrator

# Verify there is NO NGINX in the WordPress container
docker exec wordpress which nginx
# Expected: returns nothing (exit code 1)

# View wp-config.php database settings
docker exec wordpress wp config get --allow-root | grep -E "DB_|REDIS"

# Check installed plugins
docker exec wordpress wp plugin list --allow-root
# Expected: redis-cache listed as active
```

---

## 9. Verifying Redis

```bash
# Ping Redis
docker exec redis redis-cli PING
# Expected: PONG

# Check cached keys (run after visiting the WordPress site)
docker exec redis redis-cli DBSIZE
# Expected: > 0 (non-zero after first page load)

docker exec redis redis-cli INFO keyspace
# Shows which databases have keys

# Verify Redis status from WordPress
docker exec wordpress wp redis status --allow-root
# Expected: Status: Connected
```

---

## 10. Verifying Bonus Services

### Adminer
```bash
# Verify the container is running
docker ps | grep adminer

# Verify it has no NGINX
docker exec adminer which nginx   # should return nothing

# Access in browser: https://nakhalil.42.fr/adminer
# Login: Server=mariadb, User=nakhalil, Password=(secrets/db_password.txt), DB=wordpress_db
```

### Static Site
```bash
# Verify no PHP in the container
docker exec static_site which php   # should return nothing

# Access in browser: https://nakhalil.42.fr/static/
```

### FTP
```bash
# Test FTP login
ftp localhost 21
# Name: ftpuser
# Password: (contents of secrets/ftp_password.txt)
ftp> ls       # should list WordPress files (/var/www/html)
ftp> quit

# Verify FTP can only access the wordpress volume (chroot test)
ftp localhost 21
ftp> cd ..    # should fail or stay in /var/www/html
```

### cAdvisor
```bash
# Verify the container is running
docker ps | grep cadvisor

# Access in browser: http://localhost:8080
# Shows real-time CPU, memory, network graphs for each container
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
docker exec -it cadvisor sh    # cadvisor has no bash, use sh
```

---

## 12. Reading Logs

```bash
docker logs -f nginx        # TLS errors, proxy errors, access log
docker logs -f wordpress    # wp_setup.sh output, PHP-FPM startup
docker logs -f mariadb      # init_db.sh output, SQL errors
docker logs -f redis        # startup, connection events
docker logs -f ftp          # vsftpd connection log
```

---

## 13. Persistence Test (Reboot)

```bash
# 1. Make a visible change first (post a comment, publish a post)

# 2. Reboot
sudo reboot

# 3. After reboot, start the project
cd ~/Documents/inception
make up

# 4. Verify data survived
docker exec mariadb mariadb -u nakhalil -p$(cat secrets/db_password.txt) wordpress_db \
  -e "SELECT post_title FROM wp_posts WHERE post_status='publish';"

# 5. Open https://nakhalil.42.fr — site loads, change is still there
```

---

## 14. Live Monitoring

```bash
# Real-time CPU/Memory/IO for all containers (like htop for Docker)
docker stats

# Per-container breakdown with graphs: http://localhost:8080
# (cAdvisor — shows both host and container metrics)
```

---

## 15. Quick Cleanup Reference

```bash
# Evaluator's full wipe (what they run before your defense):
docker stop $(docker ps -qa)
docker rm $(docker ps -qa)
docker rmi -f $(docker images -qa)
docker volume rm $(docker volume ls -q)
docker network rm $(docker network ls -q) 2>/dev/null
sudo rm -rf /home/nakhalil/data/*

# Our Makefile equivalent:
make fclean    # handles all of the above in one command
make all       # rebuild everything from scratch
```

> ⚠️ `make fclean` deletes `/home/nakhalil/data/` — all WordPress and MariaDB data is permanently gone. Only use it for a full rebuild or when instructed by the evaluator.
