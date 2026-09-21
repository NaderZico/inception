# Inception — Docker & System Commands Cheat Sheet

Commands you'll actually need during evaluation and day-to-day work. All examples use the real container and volume names from this project.

---

## 1. Project Lifecycle (via Makefile)

```bash
make all        # build images + start all containers (first run)
make up         # start containers (images already built)
make down       # stop & remove containers (volumes preserved)
make stop       # pause running containers (don't remove)
make start      # resume paused containers
make status     # show container status
make logs       # follow all logs in real-time
make clean      # down + prune unused images/networks
make fclean     # everything: down, prune, delete /home/nakhalil/data
make re         # fclean + all (full rebuild from scratch)
```

---

## 2. Container Interaction

### Enter a running container
```bash
docker exec -it <name> bash
# Examples:
docker exec -it wordpress bash
docker exec -it mariadb bash
docker exec -it nginx bash
docker exec -it redis bash
```
If `bash` isn't available (rare), use `sh`.

### Follow a container's logs
```bash
docker logs -f <name>
docker logs -f wordpress   # useful when debugging wp_setup.sh
docker logs -f mariadb     # useful when debugging init_db.sh
docker logs -f nginx       # check TLS errors, proxy errors
```

### Check all containers (running and stopped)
```bash
docker ps -a
```
Useful when a container keeps crashing — it shows `Exited` status and you can then `docker logs` it.

---

## 3. Inspecting Docker Objects

### Inspect a volume (prove it maps to the right host path)
```bash
docker volume inspect srcs_mariadb_vol
docker volume inspect srcs_wordpress_vol
```
Look for `"Mountpoint"` in the output — it shows where Docker stores the data, and `"Options"` shows the bind device path (`/home/nakhalil/data/mariadb`).

> **Note:** Volume names are prefixed with the Compose project name (`srcs_`) because the compose file is in the `srcs/` directory.

### Inspect a container (check network, mounts, env vars)
```bash
docker inspect mariadb
docker inspect wordpress
```
Secrets do NOT appear here — they are mounted as files, not environment variables.

### List all networks
```bash
docker network ls
# You should see srcs_inception_net
docker network inspect srcs_inception_net
# Shows which containers are connected and their internal IPs
```

### List all volumes
```bash
docker volume ls
# You should see srcs_mariadb_vol and srcs_wordpress_vol
```

---

## 4. Inside the Containers

### MariaDB — verify the database and users
```bash
docker exec -it mariadb bash
mariadb -u root -p
# enter root password from secrets/db_root_password.txt

SHOW DATABASES;               -- should show wordpress_db
USE wordpress_db;
SHOW TABLES;                  -- should show wp_posts, wp_users, etc.
SELECT user, host FROM mysql.user;  -- verify nakhalil user exists
```

Or without entering bash:
```bash
docker exec mariadb mariadb -u nakhalil -p$(cat secrets/db_password.txt) wordpress_db -e "SHOW TABLES;"
```

### WordPress — WP-CLI commands
```bash
docker exec -it wordpress bash
wp user list --allow-root                          # list all users (verify 2 exist)
wp user get nakhalil_master --allow-root           # view admin details
wp plugin list --allow-root                        # list installed plugins
wp redis status --allow-root                       # check if Redis cache is active
wp redis flush --allow-root                        # clear the Redis cache manually
wp config get --allow-root                         # view wp-config.php values
```

### Redis — verify it's connected and caching
```bash
docker exec -it redis redis-cli
PING                # should return PONG
INFO keyspace       # shows the databases and number of cached keys
DBSIZE              # number of keys currently cached
```

### NGINX — verify TLS and config
```bash
docker exec -it nginx bash
nginx -t                                           # test config syntax
openssl x509 -in /etc/ssl/certs/nginx-selfsigned.crt -text -noout  # inspect the cert
cat /etc/nginx/conf.d/default.conf                 # check DOMAIN_NAME was replaced
```

---

## 5. Debugging Failures

### A container keeps restarting — what to do
```bash
docker ps -a                      # see exit codes
docker logs <container>           # read the error
# Common causes:
# - MariaDB: permission issues on /var/lib/mysql
# - WordPress: MariaDB wasn't ready yet (usually self-resolves)
# - NGINX: config syntax error
```

### WordPress can't connect to MariaDB
```bash
# 1. Check MariaDB is running
docker ps | grep mariadb

# 2. Check the credentials match
cat secrets/db_password.txt
docker exec mariadb mariadb -u nakhalil -p<password> wordpress_db -e "SELECT 1;"

# 3. Check WordPress config
docker exec wordpress cat /var/www/html/wp-config.php | grep DB_
```

### Force a full rebuild (when volume data is stale or corrupted)
```bash
make fclean    # removes containers, images, AND /home/nakhalil/data
make all       # fresh start
```

---

## 6. Live Monitoring

### Terminal resource monitor
```bash
docker stats
```
Shows CPU%, Memory, Network I/O, and Block I/O for all running containers in real-time. Equivalent to `htop` but for containers.

### cAdvisor web dashboard
Open: `http://localhost:8080`  
Shows historical graphs, per-container CPU and memory, and Docker metadata.

---

## 7. Checking TLS from the Command Line

### Test that NGINX only accepts TLSv1.2 and TLSv1.3
```bash
# Should succeed:
curl -k --tlsv1.2 https://nakhalil.42.fr
curl -k --tlsv1.3 https://nakhalil.42.fr

# Should FAIL (TLS 1.1 is disabled):
curl -k --tlsv1.1 --tls-max 1.1 https://nakhalil.42.fr
```
`-k` skips certificate validation (needed because it's self-signed).

### Inspect the certificate
```bash
echo | openssl s_client -connect nakhalil.42.fr:443 2>/dev/null | openssl x509 -noout -text
```
Look for `Subject: CN=nakhalil.42.fr` and the protocol version.

---

## 8. FTP Testing

```bash
ftp localhost 21
# Connected to localhost.
# Name: ftpuser       (from .env FTP_USER)
# Password: <contents of secrets/ftp_password.txt>
ftp> ls                # should list /var/www/html contents
ftp> put localfile.txt # upload a file
ftp> quit
```

Or with `lftp` (more informative):
```bash
lftp -u ftpuser,<password> localhost
lftp> ls
lftp> exit
```

---

## 9. Networking Quick Reference

| Connection | Protocol | Port | Internal hostname |
|---|---|---|---|
| Browser → NGINX | HTTPS (TLS) | 443 | — |
| NGINX → WordPress | FastCGI | 9000 | `wordpress` |
| WordPress → MariaDB | MySQL | 3306 | `mariadb` |
| WordPress → Redis | RESP | 6379 | `redis` |
| NGINX → Adminer | HTTP | 8080 | `adminer` |
| NGINX → Static Site | HTTP | 3000 | `static_site` |
| External → cAdvisor | HTTP | 8080 | — (host-published) |
| External → FTP | FTP | 21, 21100–21110 | — (host-published) |

---

## 10. Quick Cleanup Reference

```bash
docker system prune -f            # remove stopped containers, dangling images, unused networks
docker system prune -af           # same but also removes unused (not just dangling) images
docker system prune -af --volumes # also deletes unused volumes (DANGER: data loss)
docker volume prune               # remove only unused volumes
docker image prune -a             # remove only unused images
```

> ⚠️ `make fclean` already handles all of this plus deleting `/home/nakhalil/data`. Use it instead of running prune commands manually.
