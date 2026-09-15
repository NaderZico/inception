# User Documentation

This guide explains how an end user or administrator can interact with the Inception stack.

## 1. Understand What Services Are Provided

| Service | Description | Access |
|---|---|---|
| **WordPress** | The main application — a fully functional blog running over HTTPS | `https://nakhalil.42.fr` |
| **MariaDB** | The backend database storing all WordPress content, users, and settings | Internal only |
| **Redis** | In-memory cache that speeds up WordPress by avoiding redundant database queries | Internal only |
| **Adminer** | Web-based GUI to visually browse and manage the MariaDB database | `https://nakhalil.42.fr/adminer` |
| **Static Site** | A lightweight HTML page served without PHP | `https://nakhalil.42.fr/static/` |
| **cAdvisor** | Real-time dashboard showing CPU, memory, and network usage per container | `http://localhost:8080` |
| **FTP Server** | Allows uploading/downloading files directly into the WordPress directory via FTP | `localhost:21` |

All web traffic enters through NGINX on port 443 (HTTPS). Internal services are not reachable from outside the Docker network.

---

## 2. Start, Stop, and Manage the Project (Makefile Rules)

All commands must be run from the **project root directory** (where the `Makefile` is located).

### Core Lifecycle & Management Commands

| Command | Effect |
|---|---|
| `make all` | Build all Docker images and start the entire infrastructure (default target) |
| `make secrets` | Initialize missing password and user files in `secrets/` with secure permissions |
| `make build` | Prepare host data directories (`/home/nakhalil/data`) and build all Docker images without starting them |
| `make up` | Start all containers in detached mode using existing images |
| `make down` | Stop and remove all containers and the Docker network (persistent data on disk is preserved) |
| `make stop` | Pause all running containers without removing them |
| `make start` | Resume paused containers |
| `make status` | View the status and health of all containers (`docker compose ps`) |
| `make logs` | Follow and stream real-time logs from all running containers (`docker compose logs -f`) |
| `make clean` | Stop containers and remove unused Docker cache and stopped containers (`down` + `prune -f`) |
| `make fclean` | Complete purge: removes containers, networks, all Docker images, volumes, and wipes persistent host data (`/home/nakhalil/data`) |
| `make re` | Full rebuild: runs `fclean` followed by `all` to rebuild everything from scratch |

### Individual Service Targets

You can build and restart a single service independently without affecting the rest of the stack:

| Command | Effect |
|---|---|
| `make mariadb` | Rebuild and start only the **MariaDB** container |
| `make wordpress` | Rebuild and start only the **WordPress** container |
| `make nginx` | Rebuild and start only the **NGINX** container |
| `make redis` | Rebuild and start only the **Redis** cache container |
| `make adminer` | Rebuild and start only the **Adminer** web GUI container |
| `make static_site` | Rebuild and start only the **Static Site** container |
| `make cadvisor` | Rebuild and start only the **cAdvisor** metrics container |
| `make ftp` | Rebuild and start only the **FTP** server container |

> **Note:** 
> - Use `make stop` and `make start` for temporary pauses (keeps container state intact).
> - Use `make down` and `make up` when updating configuration or restarting containers (data on disk is preserved).
> - Use `make fclean` only when you want to wipe all databases, uploaded media, and start completely fresh.

---

## 3. Access the Website and Administration Panels

Make sure the project is running (`make all` or `make up`) and that your `/etc/hosts` file maps `nakhalil.42.fr` to `127.0.0.1`.

| Panel | URL | Notes |
|---|---|---|
| WordPress site | `https://nakhalil.42.fr` | Main public site |
| WordPress admin | `https://nakhalil.42.fr/wp-admin` | Log in with `WP_ADMIN_USER` credentials |
| Adminer | `https://nakhalil.42.fr/adminer` | Select "MySQL", server: `mariadb` |
| Static site | `https://nakhalil.42.fr/static/` | Trailing slash required |
| cAdvisor | `http://localhost:8080` | No login required |
| FTP | `ftp localhost 21` | Username: value of `FTP_USER` in `srcs/.env` |

> Your browser will show a **"Not Secure" warning** because the SSL certificate is self-signed. This is expected. Proceed through the warning to access the site.

---

## 4. Locate and Manage Credentials

Credentials are split between two locations for security reasons. Passwords are never stored in the repository.

### Non-sensitive configuration — `srcs/.env`

Contains usernames, database name, domain, and other non-secret values:
- `DOMAIN_NAME` — the site domain (`nakhalil.42.fr`)
- `MYSQL_USER` — the MariaDB username
- `MYSQL_DATABASE` — the database name
- `WP_ADMIN_USER` — the WordPress admin username
- `WP_USER` — the WordPress second user username
- `FTP_USER` — the FTP username
- `FTP_PASV_ADDRESS` — the passive FTP return address (default: `127.0.0.1`)

### Passwords — `secrets/` directory

Each password is stored in a plain text file. These files must exist before running `make all`:

| File | Used for |
|---|---|
| `secrets/db_password.txt` | MariaDB user password |
| `secrets/db_root_password.txt` | MariaDB root password |
| `secrets/wp_admin_password.txt` | WordPress admin login |
| `secrets/wp_user_password.txt` | WordPress second user login |
| `secrets/ftp_password.txt` | FTP user login |

> The `secrets/` directory is in `.gitignore` and must never be committed to the repository.

---

## 5. Check That the Services Are Running Correctly

### Step 1 — Check container status

```bash
make status
```

All 8 containers should show status `running`:

```
NAME          STATUS
nginx         running
wordpress     running
mariadb       running
redis         running
adminer       running
static_site   running
cadvisor      running
ftp           running
```

### Step 2 — Verify the website is reachable

```bash
curl -k https://nakhalil.42.fr | grep -i wordpress
```

You should see HTML output containing WordPress markup. `-k` skips certificate validation for the self-signed cert.

### Step 3 — Verify MariaDB has the WordPress database

```bash
docker exec mariadb mariadb -u nakhalil -p"$(cat secrets/db_password.txt)" wordpress_db -e "SHOW TABLES;" 2>/dev/null
```

You should see a list of `wp_*` tables.

### Step 4 — Verify Redis is caching

```bash
docker exec redis redis-cli PING
```

Should return `PONG`. To confirm WordPress is using it:

```bash
docker exec wordpress wp redis status --allow-root
```

Should show `Status: Connected`.

### Step 5 — View logs if something is wrong

```bash
make logs                         # stream all container logs
docker logs -f <container_name>   # stream a specific container's logs
# Example: docker logs -f wordpress
```
