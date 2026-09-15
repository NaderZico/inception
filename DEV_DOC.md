# Developer Documentation

This document describes how a developer can set up, build, manage, and understand the data flow of the Inception infrastructure from scratch.

---

## 1. Set Up the Environment from Scratch

Before building, you must configure three things on the host machine.

### Prerequisites

- Docker Engine installed (`docker --version`)
- Docker Compose plugin installed (`docker compose version`)
- `sudo` access (needed to create the data directories under `/home/nakhalil/`)

### Step 1 — Map the domain in `/etc/hosts`

NGINX uses `nakhalil.42.fr` as the server name. Your machine must resolve it to localhost:

```bash
sudo sh -c 'echo "127.0.0.1 nakhalil.42.fr" >> /etc/hosts'
```

Verify: `ping nakhalil.42.fr` should resolve to `127.0.0.1`.

### Step 2 — Configure `srcs/.env`

The `.env` file holds all non-sensitive configuration. It is already provided in the repository. Confirm the values match your setup (the domain name and login must match your 42 username):

```env
DOMAIN_NAME=nakhalil.42.fr
MYSQL_DATABASE=wordpress_db
MYSQL_USER=nakhalil
WP_TITLE=Inception_42
WP_ADMIN_USER=nakhalil_master
WP_ADMIN_EMAIL=nakhalil@student.42.fr
WP_USER=student_user
WP_USER_EMAIL=student@student.42.fr
FTP_USER=ftpuser
FTP_PASV_ADDRESS=127.0.0.1
```

### Step 3 — Create the `secrets/` directory and password files

Passwords are never stored in the repository. Create the `secrets/` directory and populate each file with your chosen password (no trailing newline is fine, Docker reads the raw content):

```bash
mkdir -p secrets
echo "your_db_user_password"   > secrets/db_password.txt
echo "your_db_root_password"   > secrets/db_root_password.txt
echo "your_wp_admin_password"  > secrets/wp_admin_password.txt
echo "your_wp_user_password"   > secrets/wp_user_password.txt
echo "your_ftp_password"       > secrets/ftp_password.txt
```

> `secrets/` is in `.gitignore` — never commit these files.

---

## 2. Build and Launch the Project

All orchestration is done via the `Makefile` at the project root. It calls `docker compose -f srcs/docker-compose.yml`.

### First run

```bash
make all
```

This runs three steps in sequence:

1. **`make secrets`**
   - Automatically initializes any missing password or user files in `secrets/` with secure 600 permissions if not already present.

2. **`make build`**
   - Creates `/home/nakhalil/data/mariadb` and `/home/nakhalil/data/wordpress` on the host (the volume backing directories).
   - Fixes ownership of those directories to the current user.
   - Runs `docker compose build` — builds all 8 Docker images from their respective `Dockerfile`s in `srcs/requirements/`.

3. **`make up`**
   - Runs `docker compose up -d` — creates the `inception_net` network, mounts the named volumes, applies Docker secrets, and starts all 8 containers in detached mode.

### Subsequent runs (images already built)

```bash
make up      # start containers without rebuilding
make down    # stop and remove containers (data on disk preserved)
```

### Rebuild a single service

Each service has its own Makefile target. This rebuilds only that image and restarts only that container:

```bash
make mariadb      # rebuild + restart MariaDB
make wordpress    # rebuild + restart WordPress
make nginx        # rebuild + restart NGINX
make redis        # rebuild + restart Redis
make adminer      # rebuild + restart Adminer
make static_site  # rebuild + restart the static site
make cadvisor     # rebuild + restart cAdvisor
make ftp          # rebuild + restart the FTP server
```

### Force a full rebuild from scratch

```bash
make re    # equivalent to: make fclean && make all
```

This wipes all containers, images, volumes, and the host data directories, then rebuilds everything.

---

## 3. Manage Containers and Volumes

### Container lifecycle

```bash
make status   # show running state of all containers (docker compose ps)
make stop     # pause all containers (state preserved)
make start    # resume paused containers
make down     # stop and remove containers + network (data on disk preserved)
make logs     # follow all container logs in real-time
```

### Inspect a specific container

```bash
docker logs -f <name>           # stream logs (e.g. docker logs -f wordpress)
docker exec -it <name> bash     # open a shell inside the container
docker inspect <name>           # full JSON metadata (network, mounts, config)
```

### Inspect volumes — verify host path binding

```bash
docker volume ls
# Shows: srcs_mariadb_vol, srcs_wordpress_vol

docker volume inspect srcs_mariadb_vol
docker volume inspect srcs_wordpress_vol
```

In the output, `Options.device` confirms the physical host path the volume is bound to (`/home/nakhalil/data/mariadb` and `/home/nakhalil/data/wordpress`).

### Inspect the Docker network

```bash
docker network ls
# Shows: srcs_inception_net

docker network inspect srcs_inception_net
# Lists all connected containers and their internal IPs
```

### Live resource monitoring

```bash
docker stats    # terminal dashboard: CPU%, memory, network I/O per container
```

---

## 4. Data Storage and Persistence

Containers are ephemeral — data written inside a container is lost if the container is removed. The project uses two **Docker named volumes** to persist state beyond the container lifecycle.

### How the volumes work

Both volumes use the `local` driver with the `bind` option, which links them to a specific host directory:

| Volume | Host path | Container path | Container |
|---|---|---|---|
| `srcs_mariadb_vol` | `/home/nakhalil/data/mariadb` | `/var/lib/mysql` | MariaDB |
| `srcs_wordpress_vol` | `/home/nakhalil/data/wordpress` | `/var/www/html` | WordPress (rw), NGINX (ro), FTP (rw) |

The host directories are created by `make build` before the containers start. Docker mounts them into the containers at runtime.

### What persists

- **MariaDB data** (`/home/nakhalil/data/mariadb`): Raw MySQL data files — all WordPress posts, users, settings, and plugin data live here.
- **WordPress files** (`/home/nakhalil/data/wordpress`): WordPress core, themes, plugins, and uploaded media. These files are shared between WordPress (read/write), NGINX (read-only for serving static assets), and FTP (read/write for remote file management).

### Survival across operations

| Operation | Containers | Images | Volume data on disk |
|---|---|---|---|
| `make stop` / `make start` | Paused / Resumed | ✅ Kept | ✅ Kept |
| `make down` / `make up` | Removed / Re-created | ✅ Kept | ✅ Kept |
| `make fclean` / `make re` | Removed | ❌ Deleted | ❌ **Deleted** |

> `make fclean` explicitly runs `sudo rm -rf /home/nakhalil/data`. Use it only when you want a completely fresh first-run state.
