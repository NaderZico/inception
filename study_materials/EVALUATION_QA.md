# Inception — Master Evaluation Study Guide & Q&A

This document is the **complete, all-in-one preparation guide** for the 42 Inception evaluation. It mirrors every section of the official evaluation sheet in order, with:
1. The **exact evaluation criteria** (what the evaluator checks).
2. **Commands to demonstrate compliance** (what to run).
3. **Deep theoretical explanations** of every required concept.

---

## Table of Contents
1. [Phase 0: Preliminaries & Immediate Failure Traps](#phase-0-preliminaries--immediate-failure-traps)
2. [Section 1: Core Concepts — Docker, Images, Containers, Compose, VMs](#section-1-core-concepts)
3. [Section 2: Simple Setup (HTTPS, SSL, WordPress)](#section-2-simple-setup)
4. [Section 3: Docker Basics & Dockerfile Best Practices](#section-3-docker-basics--dockerfile-best-practices)
5. [Section 4: Docker Network & Inter-Container Communication](#section-4-docker-network)
6. [Section 5: NGINX with SSL/TLS](#section-5-nginx-with-ssltls)
7. [Section 6: WordPress with PHP-FPM & Its Volume](#section-6-wordpress-with-php-fpm--its-volume)
8. [Section 7: MariaDB & Its Volume](#section-7-mariadb--its-volume)
9. [Section 8: Persistence! (The VM Reboot Test)](#section-8-persistence)
10. [Section 9: Configuration Modification](#section-9-configuration-modification)
11. [Section 10: Docker Secrets vs Environment Variables](#section-10-docker-secrets-vs-environment-variables)
12. [Section 11: PID 1, Process Management & Signals](#section-11-pid-1-process-management--signals)
13. [Section 12: The Makefile & Orchestration Rules](#section-12-the-makefile--orchestration-rules)
14. [Section 13: Bonus Services](#section-13-bonus-services)

---

## Phase 0: Preliminaries & Immediate Failure Traps

Before anything else, the evaluator will inspect your repository and configuration for automatic-fail conditions. If any of these fail, the evaluation terminates immediately with a score of 0.

### The Evaluator's Cleanup Commands
The official evaluation sheet instructs the evaluator to run these commands before starting:
```bash
# 1. Wipe all Docker objects
docker stop $(docker ps -qa); docker rm $(docker ps -qa); docker rmi -f $(docker images -qa); docker volume rm $(docker volume ls -q); docker network rm $(docker network ls -q) 2>/dev/null

# 2. Remove host-mapped volume data (replace nakhalil with evaluated student's login)
sudo rm -rf /home/nakhalil/data/*
```

> **What this does**: Ensures a 100% clean state — no leftover containers, images, volumes, networks, or persistent data from previous runs. The evaluator wants to see that `make all` builds everything from scratch.

---

### Immediate Disqualification Checklist

| Evaluation Check | Subject Rule | How Our Project Complies |
| :--- | :--- | :--- |
| **Secrets in Git** | *"If any credentials, API keys, or passwords are available in the git repository and outside of secrets during the evaluation, the evaluation stops and the mark is 0."* | All passwords live in `secrets/*.txt` files which are gitignored. The `.env` file contains **only** non-sensitive config (usernames, domain name, database name, email addresses, site title). Zero passwords in Git history. |
| **`network: host`** | *"There mustn't be 'network: host' in docker-compose.yml. Otherwise, the evaluation ends now."* | We use a custom user-defined bridge network `inception_net`. No `network_mode: host`. |
| **`links:` / `--link`** | *"There mustn't be 'links:' or '--link' in any file or script. Otherwise, the evaluation ends now."* | We use Docker's automatic DNS service discovery. Zero instances of `--link` or `links:`. |
| **`network(s)` present** | *"There must be 'network(s)' in docker-compose.yml. Otherwise, the evaluation ends now."* | `networks: [ inception_net ]` is defined and attached to every container. |
| **Hacky background loops** | *"If you see 'tail -f' or any command run in background in any of them or in the ENTRYPOINT section, the evaluation ends now."* | No `tail -f /dev/null`, `tail -f /dev/random`, `sleep infinity`, or `while true`. Every entrypoint script ends with `exec <daemon>` in the foreground. |
| **`bash` or `sh` as keep-alive** | *"Same thing if 'bash' or 'sh' are used but not for running a script (e.g. 'nginx & bash')."* | All ENTRYPOINT directives invoke specific setup scripts (`["/usr/local/bin/nginx_setup.sh"]`), never standalone shells. No service is run in the background with `&`. |
| **Infinite loops in scripts** | *"Ensure none of them runs an infinite loop. Examples: 'sleep infinity', 'tail -f /dev/null', 'tail -f /dev/random'."* | None of our scripts contain infinite loops. The only loop is a `until mariadb-admin ping` health-check in `wp_setup.sh` that exits as soon as MariaDB responds. |
| **Base image** | *"The containers must be built from the penultimate stable version of Alpine or Debian."* | All 8 Dockerfiles use `FROM debian:bookworm` (Debian 12, the penultimate stable version). |
| **Entrypoint background processes** | *"If the entrypoint is a script, ensure it runs no program in background (e.g. 'nginx & bash')."* | All entrypoint scripts run setup sequentially, then call `exec <daemon>` which **replaces** the shell process. No `&` backgrounding anywhere. |

---

## Section 1: Core Concepts

> **Eval sheet**: *"The evaluated learner has to explain to you in simple terms: How Docker and docker compose work, the difference between a Docker image used with docker compose and without, the benefit of Docker compared to VMs, the pertinence of the directory structure."*

---

### Q: What is Docker?

> **Answer**:
> Docker is a platform that packages and runs applications inside isolated environments called **containers**. A container bundles an application with everything it needs to run (code, libraries, system tools, configuration files) so it runs identically on any machine — your laptop, a server, or the cloud.
>
> Docker is NOT a virtual machine. It does not emulate hardware or boot an entire operating system. Instead, containers run directly on the host machine's Linux kernel, using two kernel features for isolation:
>
> 1. **Namespaces** — isolate what a process can **see**:
>    - `pid` namespace: The container gets its own process tree. The first process inside thinks it's PID 1, even though it's actually PID 54321 on the host.
>    - `net` namespace: The container gets its own network interfaces, IP address, and port bindings, completely separate from the host's network.
>    - `mnt` namespace: The container gets its own filesystem. It can only see the files Docker gives it, not the host's files (unless you explicitly mount a volume).
>    - `uts` namespace: The container gets its own hostname.
>    - `ipc` namespace: Inter-process communication is isolated between containers.
>
> 2. **Control Groups (cgroups)** — limit what a process can **use**:
>    - You can restrict how much CPU, RAM, disk I/O, and network bandwidth a container can consume.
>    - This prevents one container from starving others of resources.

---

### Q: What is a Docker Image?

> **Answer**:
> A Docker image is a **read-only, layered filesystem snapshot** that contains everything needed to run an application: the operating system base, installed packages, configuration files, and the application code.
>
> **How it's built**:
> You write a `Dockerfile` — a text file with a sequence of instructions. Each instruction creates a new **layer**:
> ```dockerfile
> FROM debian:bookworm         # Layer 1: Base Debian OS
> RUN apt-get update && \      # Layer 2: Install packages
>     apt-get install -y nginx
> COPY nginx.conf /etc/nginx/  # Layer 3: Add config file
> ENTRYPOINT ["nginx"]         # Metadata: what to run
> ```
>
> When Docker builds this file, it executes each instruction and saves the resulting filesystem state as a layer. Layers are **stacked** on top of each other and **cached** — if an instruction hasn't changed, Docker reuses the cached layer, making rebuilds very fast.
>
> **Key properties of images**:
> - **Immutable**: Once built, an image never changes. You can't modify it — you build a new one.
> - **Shareable**: Images can be pushed to registries (like DockerHub) and pulled by anyone.
> - **Tagged**: Images have names and tags, like `nginx:inception` or `debian:bookworm`. The tag identifies a specific version.
> - **Lightweight**: Images only contain what's needed. Our NGINX image is ~150MB, not the 4GB a full VM would need.

---

### Q: What is a Docker Container?

> **Answer**:
> A container is a **running instance of a Docker image**. If an image is a blueprint (like a class in programming), a container is a live instance of it (like an object).
>
> When you run `docker run nginx:inception`, Docker:
> 1. Takes the read-only image layers.
> 2. Adds a thin **writable layer** on top (called the container layer).
> 3. Creates new Linux namespaces for isolation.
> 4. Launches the `ENTRYPOINT` process inside that isolated environment.
>
> **Key properties of containers**:
> - **Ephemeral**: By default, everything written inside a container is lost when it's removed (`docker rm`). The writable layer is temporary.
> - **Isolated**: Each container has its own filesystem, network, and process tree.
> - **Lightweight**: Containers share the host kernel, so starting a container takes milliseconds (not minutes like a VM).
> - **One process per container**: The best practice (and the 42 subject requirement) is to run one main service per container. Our project has one container for NGINX, one for MariaDB, one for WordPress, etc.
>
> **Image vs Container analogy**:
> | Concept | Analogy | Docker |
> |---|---|---|
> | Blueprint | Architectural plan | Docker Image |
> | Building | Physical house built from the plan | Docker Container |
> | You can build many houses from one plan | Multiple containers from one image | `docker run` creates a new container each time |

---

### Q: What is Docker Compose?

> **Answer**:
> Docker Compose is a tool for defining and running **multi-container** Docker applications. Instead of typing long `docker run` commands for each container, you write a single YAML file (`docker-compose.yml`) that describes your entire infrastructure declaratively.
>
> **What docker-compose.yml defines**:
> - **Services**: Each container (mariadb, wordpress, nginx, redis, etc.) with its build context, image name, restart policy.
> - **Networks**: The virtual network connecting all containers (`inception_net`).
> - **Volumes**: Persistent storage that survives container restarts (`mariadb_vol`, `wordpress_vol`).
> - **Secrets**: Sensitive files (passwords) mounted securely into containers.
> - **Dependencies**: Which services must start before others (`depends_on`).
> - **Environment**: Configuration variables loaded from `.env`.
>
> **Key commands**:
> | Command | What it does |
> |---|---|
> | `docker compose build` | Reads each service's Dockerfile and builds the image |
> | `docker compose up -d` | Creates containers, networks, volumes, and starts everything in the background |
> | `docker compose down` | Stops and removes containers + network (volumes preserved) |
> | `docker compose down -v` | Same as above, but also removes volumes |
> | `docker compose ps` | Shows the status of all containers |
> | `docker compose logs` | Shows logs from all services |
>
> **Without Compose**, you'd need to manually run commands like:
> ```bash
> docker network create inception_net
> docker volume create mariadb_vol
> docker run -d --name mariadb --network inception_net -v mariadb_vol:/var/lib/mysql \
>   -e MYSQL_USER=nakhalil -e MYSQL_DATABASE=wordpress_db mariadb:inception
> docker run -d --name wordpress --network inception_net --depends-on mariadb ...
> docker run -d --name nginx --network inception_net -p 443:443 ...
> ```
> That's error-prone and unmaintainable for 8 services. Compose reduces it to `docker compose up -d`.

---

### Q: What is the difference between a Docker image used with docker compose and without?

> **Answer**:
> The underlying **Docker image is 100% identical**. It's the same immutable, read-only stack of filesystem layers built from a Dockerfile. Nothing about the image changes based on how you run it.
>
> The difference is entirely in **how the container is created and managed at runtime**:
> - **Without Compose**: You manually specify networks, volumes, environment variables, ports, and dependencies on the command line for each `docker run` invocation.
> - **With Compose**: All of that is declared once in `docker-compose.yml`. Compose handles the orchestration — creating networks before containers, starting dependencies first, connecting volumes, and managing the lifecycle of all services as a single unit.

---

### Q: What is the benefit of Docker compared to Virtual Machines?

> **Answer**:
>
> | Aspect | Virtual Machines | Docker Containers |
> |---|---|---|
> | **How it works** | A **hypervisor** (e.g., VirtualBox, VMware) emulates virtual hardware (CPU, RAM, NIC, disk) and boots a complete guest operating system with its own kernel | Containers share the host's Linux kernel. Docker uses namespaces and cgroups to isolate processes without emulating hardware |
> | **Size** | Gigabytes (full OS: kernel + userspace + apps) | Megabytes (only app + its dependencies) |
> | **Boot time** | Minutes (must boot a full OS kernel) | Milliseconds to seconds (just starts a process) |
> | **Performance** | Hypervisor overhead on every CPU instruction | Near bare-metal speed (native kernel, no emulation) |
> | **RAM usage** | Each VM reserves dedicated RAM (e.g., 2GB per VM) | Containers share host RAM, using only what they need |
> | **Isolation level** | Hardware-level (strongest — separate kernel) | OS-level (lighter — shared kernel, namespace isolation) |
> | **Density** | ~10 VMs per host | ~100+ containers per host |
>
> **When VMs are better**: When you need to run different operating systems (e.g., Linux + Windows on the same host) or need the strongest possible isolation (security-critical workloads).
>
> **When Docker is better**: When you're running many Linux-based services on the same host and need them to be lightweight, fast to start, and easy to deploy. This is exactly our Inception use case — 8 services on one machine.

---

### Q: Explain the pertinence of the required directory structure.

> **Answer**:
> The directory structure strictly enforces separation of concerns:
> ```
> inception/
> ├── Makefile                  # Build orchestrator (root level)
> ├── README.md                 # Project documentation
> ├── USER_DOC.md               # End-user instructions
> ├── DEV_DOC.md                # Developer instructions
> ├── secrets/                  # Passwords (gitignored, never in Git)
> │   ├── db_password.txt
> │   ├── db_root_password.txt
> │   ├── wp_admin_password.txt
> │   ├── wp_user_password.txt
> │   └── ftp_password.txt
> └── srcs/
>     ├── .env                  # Non-sensitive configuration
>     ├── docker-compose.yml    # Infrastructure definition
>     └── requirements/
>         ├── nginx/            # Each service gets its own directory
>         │   ├── Dockerfile
>         │   ├── conf/         # Service-specific config files
>         │   └── tools/        # Entrypoint/setup scripts
>         ├── wordpress/
>         ├── mariadb/
>         └── bonus/
>             ├── redis/
>             ├── ftp/
>             ├── adminer/
>             ├── static_site/
>             └── cadvisor/
> ```
>
> **Why this structure matters**:
> - **Root level**: Only the Makefile (build entry point) and documentation.
> - **`srcs/`**: All infrastructure code is isolated here. The evaluator finds `docker-compose.yml` and `.env` in one place.
> - **`srcs/requirements/<service>/`**: Each service is self-contained with its own Dockerfile, configs, and scripts. Changing MariaDB's config can't accidentally break NGINX.
> - **`bonus/`**: Clean separation between mandatory and bonus services.
> - **`secrets/`**: At root level, gitignored. Passwords never enter version control.

---

## Section 2: Simple Setup

> **Eval sheet**: *"Ensure that NGINX can be accessed by port 443 only. Ensure that a SSL/TLS certificate is used. Ensure that the WordPress website is properly installed and configured (you shouldn't see the WordPress Installation page). Open https://login.42.fr. You shouldn't be able to access the site via http://login.42.fr."*

### Demonstration Commands:
```bash
# Test HTTP port 80 (MUST be refused):
curl -I http://nakhalil.42.fr
# Expected: curl: (7) Failed to connect to nakhalil.42.fr port 80: Connection refused

# Test HTTPS port 443 (MUST succeed):
curl -kI https://nakhalil.42.fr
# Expected: HTTP/2 200 (or HTTP/1.1 200 OK)
```

### Q: Why is port 80 blocked?
> In `docker-compose.yml`, NGINX only publishes port `443:443`. Port 80 is never bound, exposed, or listened on. The `nginx.conf` only has a `listen 443 ssl;` directive — no port 80 server block exists. There is physically nothing listening on port 80.

### Q: Why is there no WordPress installation page?
> `wp_setup.sh` runs `wp core install` automatically on first boot. This command configures the site title, admin user, database connection, and marks WordPress as "installed." By the time a browser visits the site, WordPress is already fully configured.

---

## Section 3: Docker Basics & Dockerfile Best Practices

> **Eval sheet**: *"There must be one Dockerfile per service. Ensure that the Dockerfiles exist and are not empty. Make sure the evaluated learner has written their own Dockerfiles and built their own Docker images; it is forbidden to use ready-made ones or services such as DockerHub. Ensure that every container is built from the penultimate stable version of Alpine/Debian. The Docker images must have the same name as their corresponding service."*

### Q: Did you write your own Dockerfiles? Are you using DockerHub images?
> All 8 Dockerfiles are custom-written. Every Dockerfile starts from `FROM debian:bookworm` and installs packages via `apt-get`. No pre-packaged application images from DockerHub (such as `wordpress:latest` or `mariadb:latest`) are used. Only the official base Debian image is pulled, which the subject explicitly allows.

### Q: What base image are you using and why?
> `debian:bookworm` (Debian 12). The subject requires the penultimate stable version of Alpine or Debian. Debian 13 "Trixie" is the current stable, making Bookworm the penultimate. We chose Debian over Alpine because Debian has better package availability and compatibility for services like MariaDB and PHP-FPM.

### Q: What is the `latest` tag and why is it forbidden?
> `latest` is a floating pointer that automatically resolves to whatever image was most recently uploaded to a registry. It breaks **reproducibility** — a build that works today with `FROM debian:latest` might fail tomorrow when Debian releases a new major version with breaking library changes. The subject prohibits `:latest` to guarantee deterministic, reproducible builds.

### Q: Do the Docker images have the same name as their services?
> Yes. Each service in `docker-compose.yml` has an `image:` tag matching its service name:
> ```
> mariadb:inception, wordpress:inception, nginx:inception,
> redis:inception, adminer:inception, static_site:inception,
> cadvisor:inception, ftp:inception
> ```
> Verify with: `docker images`

### Q: What is a Dockerfile?
> A Dockerfile is a text file containing a sequence of instructions that Docker reads to build an image. Each instruction adds a layer to the image:
>
> | Instruction | What it does |
> |---|---|
> | `FROM debian:bookworm` | Sets the base image (starting point) |
> | `RUN apt-get install ...` | Executes a command during build, creating a new layer |
> | `COPY file /path/` | Copies files from the build context into the image |
> | `WORKDIR /path` | Sets the working directory for subsequent instructions |
> | `EXPOSE 9000` | Documents which port the container listens on (metadata only) |
> | `ENTRYPOINT ["script.sh"]` | Defines the command that runs when the container starts |
>
> **Important**: `EXPOSE` does NOT publish ports. It's just documentation. Actual port publishing happens in `docker-compose.yml` via `ports:` or `expose:`.

### Q: What is `ENTRYPOINT` vs `CMD`?
> - **`ENTRYPOINT`** defines the fixed binary or script that is **always** executed when the container starts. It cannot be overridden by arguments passed to `docker run`.
> - **`CMD`** provides **default arguments** to the ENTRYPOINT. These can be overridden when you run the container with different arguments.
>
> Example:
> ```dockerfile
> ENTRYPOINT ["nginx"]
> CMD ["-g", "daemon off;"]
> ```
> Running `docker run myimage` executes `nginx -g "daemon off;"`.
> Running `docker run myimage -t` executes `nginx -t` (CMD overridden, ENTRYPOINT stays).

### Q: What is the difference between exec-form and shell-form ENTRYPOINT?
> - **Shell-form**: `ENTRYPOINT /usr/local/bin/script.sh`
>   Docker actually runs: `/bin/sh -c "/usr/local/bin/script.sh"`. The shell (`/bin/sh`) becomes PID 1, and the script runs as a child. `SIGTERM` from `docker stop` hits the shell, NOT your daemon. The shell may not forward signals, leading to a hard `SIGKILL` after 10 seconds.
>
> - **Exec-form**: `ENTRYPOINT ["/usr/local/bin/script.sh"]`
>   Docker runs the script directly — no shell wrapper. The script (and the daemon after `exec`) becomes PID 1 and receives signals directly.
>
> We use exec-form in all our Dockerfiles.

### Q: What is a Docker layer and why does it matter?
> Every instruction in a Dockerfile (`FROM`, `RUN`, `COPY`) creates a new read-only **layer**. Layers are stacked to form the final image.
>
> **Why it matters**:
> 1. **Caching**: Docker caches layers. If an instruction hasn't changed, Docker reuses the cached layer, making rebuilds fast.
> 2. **Size**: Each layer permanently stores its changes. If you install packages in Layer 2 and clean up in Layer 3, the installed files still exist in Layer 2 (they're just hidden). That's why we do `apt-get install && rm -rf /var/lib/apt/lists/*` in a **single `RUN`** — to keep install and cleanup in the same layer.

### Q: Why do we use `--no-install-recommends` and `rm -rf /var/lib/apt/lists/*`?
> - `--no-install-recommends`: Prevents `apt` from pulling in optional/suggested packages (documentation, GUI tools), keeping images minimal.
> - `rm -rf /var/lib/apt/lists/*`: Cleans up APT's package index cache. Must be in the **same `RUN` layer** as `apt-get update` to actually save space.

---

## Section 4: Docker Network

> **Eval sheet**: *"Ensure that docker-network is used by checking the docker-compose.yml file. Then run the 'docker network ls' command to verify that a network is visible. The evaluated learner has to give you a simple explanation of docker-network."*

### Demonstration:
```bash
# Show the network exists:
docker network ls
# Output includes: srcs_inception_net   bridge   local

# Inspect the network and see all connected containers:
docker network inspect srcs_inception_net
```

### Q: What is a Docker Network? Explain in simple terms.
> A Docker network is a **virtual software switch** that lets containers communicate with each other in isolation.
>
> In our project, `srcs_inception_net` is a **user-defined bridge network**. Here's what happens under the hood:
>
> 1. **Bridge creation**: The Linux kernel creates a virtual bridge interface on the host (like `br-cdd5fb3713fe`). Think of it as a virtual Ethernet switch.
>
> 2. **Container connection**: When a container joins the network, Docker creates a virtual Ethernet cable (`veth pair`) — one end goes into the container, the other plugs into the bridge. Each container gets a private IP address (e.g., `172.20.0.2`, `172.20.0.3`).
>
> 3. **DNS resolution**: Docker runs an **embedded DNS server at `127.0.0.11`** inside every container on a user-defined network. When WordPress connects to `mariadb:3306`, the DNS resolves `mariadb` to that container's private IP. No hardcoded IPs needed.
>
> 4. **Isolation**: Only containers on the same network can reach each other. Containers on different networks are invisible to each other.
>
> **Why NOT the default `bridge` network?**
> Docker's built-in `bridge` network does NOT have automatic DNS. Containers on it can only reach each other by IP address, which changes when containers restart. A user-defined bridge provides DNS resolution by container name.

### Q: What does `docker network ls` show after cleanup vs after `make all`?
> **After cleanup** (only Docker's 3 built-in networks that always exist):
> ```
> bridge    bridge    local    ← Default network (no DNS)
> host      host      local    ← Shares host network (no isolation)
> none      null      local    ← No networking at all
> ```
> **After `make all`** (our custom network appears):
> ```
> bridge               bridge    local
> host                 host      local
> none                 null      local
> srcs_inception_net   bridge    local    ← Our project's network
> ```

### Q: Why is `network_mode: host` forbidden?
> Host networking **removes all network isolation**. The container shares the host machine's network stack directly — container ports become host ports without any NAT. If a container binds port 80, it occupies the physical host's port 80. If the container is compromised, the attacker has direct access to all host network interfaces. It also prevents multiple containers from using the same port.

### Q: Why is `--link` forbidden?
> `--link` is a **deprecated legacy feature** from 2014. It statically injected IP addresses and environment variables into `/etc/hosts` at boot time. If container A restarted and received a new IP, container B's link broke permanently. Modern user-defined bridge networks provide dynamic, automatic DNS resolution that survives container restarts.

### Q: What is the difference between `ports:` and `expose:` in `docker-compose.yml`?
> | Directive | What it does | Who can connect | Used for |
> |---|---|---|---|
> | `expose: ["3306"]` | Opens the port **only inside the Docker network** | Other containers on `inception_net` | MariaDB, WordPress (9000), Redis (6379), Adminer (8080), Static Site (3000) |
> | `ports: ["443:443"]` | **Publishes** the port to the host machine via NAT | External browsers, host machine, internet | NGINX (443), cAdvisor (8080), FTP (21) |
>
> In our architecture, **NGINX is the only web-facing entrypoint**. It reverse-proxies traffic to internal services that use `expose`. MariaDB, WordPress, and Redis are never directly accessible from outside the Docker network.

---

## Section 5: NGINX with SSL/TLS

> **Eval sheet**: *"Ensure that there is a Dockerfile. Using 'docker compose ps', ensure the container was created. Try to access the service via http (port 80) and verify that you cannot connect. Open https://login.42.fr/. The displayed page must be the configured WordPress website. The use of a TLS v1.2 or TLS v1.3 certificate is mandatory. The SSL/TLS certificate doesn't have to be recognized. A self-signed certificate warning may appear."*

### Demonstration:
```bash
# Verify container is running:
docker compose -f srcs/docker-compose.yml ps nginx

# Test port 80 is blocked:
curl -I http://nakhalil.42.fr
# Expected: Connection refused

# Test HTTPS works:
curl -kI https://nakhalil.42.fr
# Expected: HTTP/2 200

# Prove TLS v1.2 works:
curl -k --tlsv1.2 --tls-max 1.2 https://nakhalil.42.fr -o /dev/null -w "HTTP: %{http_code}\n"

# Prove TLS v1.3 works:
curl -k --tlsv1.3 https://nakhalil.42.fr -o /dev/null -w "HTTP: %{http_code}\n"

# Prove TLS v1.1 is REJECTED:
curl -k --tlsv1.1 --tls-max 1.1 https://nakhalil.42.fr
# Expected: handshake failure / protocol error
```

### Q: What is TLS (Transport Layer Security)?
> TLS is a **cryptographic protocol** that encrypts all data transmitted between a client (browser) and a server (NGINX). Without TLS, everything — passwords, cookies, page content, form submissions — travels as plain text that anyone on the network can intercept and read (a "man-in-the-middle" attack).
>
> **How the TLS handshake works** (simplified):
> 1. **Client Hello**: Browser connects and says "I support TLS 1.2 and 1.3."
> 2. **Server Hello**: NGINX responds with its SSL certificate (containing the public key) and chooses a TLS version and cipher.
> 3. **Key Exchange**: Both sides negotiate a shared symmetric encryption key using asymmetric cryptography (RSA/ECDH).
> 4. **Encrypted Communication**: All subsequent data is encrypted with the shared key.

### Q: What's the difference between TLS 1.2 and TLS 1.3?
> | | TLS 1.2 (2008) | TLS 1.3 (2018) |
> |---|---|---|
> | **Handshake speed** | 2 round trips | 1 round trip (faster page loads) |
> | **Cipher suites** | Supports old + new ciphers (some weak) | Removed all weak/legacy ciphers |
> | **Security** | Secure if configured properly | Secure by design — no weak options |
> | **Compatibility** | Works with everything (including old browsers) | All modern browsers support it |
>
> Our `nginx.conf` enforces: `ssl_protocols TLSv1.2 TLSv1.3;`
> TLS 1.0 and 1.1 are **excluded** because they have known vulnerabilities.

### Q: Where and how is the SSL certificate generated?
> The certificate is generated **at runtime** inside `nginx_setup.sh` using OpenSSL:
> ```bash
> openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
>     -keyout /etc/ssl/private/nginx-selfsigned.key \
>     -out /etc/ssl/certs/nginx-selfsigned.crt \
>     -subj "/C=FR/ST=Paris/L=Paris/O=42/OU=Inception/CN=${DOMAIN_NAME}"
> ```
>
> **Why at runtime, not at build time?** Because the `DOMAIN_NAME` variable (`nakhalil.42.fr`) comes from the `.env` file and is only available when the container starts, not when the image is built.
>
> **Parameter breakdown**:
> - `-x509`: Generate a self-signed certificate (not a Certificate Signing Request).
> - `-nodes`: No passphrase on the private key (NGINX must read it automatically at boot).
> - `-days 365`: Valid for one year.
> - `-newkey rsa:2048`: Generate a new 2048-bit RSA key pair.
> - `-subj "...CN=${DOMAIN_NAME}"`: The Common Name (CN) is set to our domain.

### Q: Why does the browser show a "Not Secure" warning?
> The certificate is **self-signed** — we generated it ourselves instead of getting it from a trusted Certificate Authority (CA) like Let's Encrypt. The encryption is just as strong (AES-GCM / RSA-2048), but the browser has no way to verify who we are. The warning says "I can't confirm this server is who it claims to be," not "the connection is unencrypted."

### Q: What is NGINX's role in this architecture?
> NGINX acts as a **reverse proxy** and **TLS termination point**:
> 1. Receives all incoming HTTPS traffic on port 443.
> 2. Decrypts TLS (terminates the encrypted connection).
> 3. Forwards requests to the appropriate backend service over the internal Docker network:
>    - PHP files → `wordpress:9000` via FastCGI protocol
>    - `/adminer` → `adminer:8080` via HTTP proxy
>    - `/static/` → `static_site:3000` via HTTP proxy
>    - Static files (CSS, JS, images) → served directly from the `wordpress_vol` volume

---

## Section 6: WordPress with PHP-FPM & Its Volume

> **Eval sheet**: *"Ensure that there is a Dockerfile. Ensure that there is no NGINX in the Dockerfile. Ensure that there is a Volume (run 'docker volume ls' then 'docker volume inspect <volume name>' — verify path contains '/home/login/data'). Ensure that you can add a comment using the available WordPress user. Sign in with the administrator account — The Admin username must not include 'admin' or 'Admin'. From the Administration dashboard, edit a page. Verify the page has been updated."*

### Demonstration:
```bash
# Verify no NGINX in WordPress container:
docker exec wordpress which nginx
# Expected: returns non-zero (not found)

# Verify volume:
docker volume ls
docker volume inspect srcs_wordpress_vol
```
Look for in the inspect output:
```json
"Options": {
    "device": "/home/nakhalil/data/wordpress",
    "o": "bind",
    "type": "none"
}
```

### Admin Username Compliance:
> **CRITICAL**: The admin username is **`nakhalil_master`** — it does **NOT** contain "admin" or "Admin" in any form (not admin, not administrator, not Admin-login, not admin-123).
> Verify: `docker exec wordpress wp user list --allow-root`

### Q: What is PHP-FPM and why do we need it?
> **PHP-FPM** stands for **FastCGI Process Manager**. It is a daemon (background service) that executes PHP code.
>
> **The problem**: NGINX is a web server, but it **cannot execute PHP code**. It can only serve static files (HTML, CSS, images) or forward requests to other services. WordPress is written entirely in PHP.
>
> **The solution**: FastCGI. When NGINX receives a request for a `.php` file (like WordPress's `index.php`):
> 1. NGINX packages the request (URL, headers, POST data) into the **FastCGI binary protocol**.
> 2. NGINX sends this package over TCP port `9000` to PHP-FPM.
> 3. PHP-FPM executes the PHP script, queries MariaDB, and generates raw HTML.
> 4. PHP-FPM sends the HTML back to NGINX via FastCGI.
> 5. NGINX sends the HTML to the browser over HTTPS.
>
> **The complete request flow**:
> ```
> Browser ──HTTPS (443)──► NGINX ──FastCGI (9000)──► PHP-FPM ──SQL (3306)──► MariaDB
>                                                            ──cache (6379)──► Redis
> ```
>
> **Why not put NGINX and PHP-FPM in the same container?**
> The 42 subject requires one service per container. This enforces the microservice architecture pattern — each container has a single responsibility and can be scaled, updated, or debugged independently.

### Q: What is FastCGI?
> FastCGI is a **binary protocol** for communication between a web server and an application server. It's the successor to CGI (Common Gateway Interface).
>
> **CGI (old)**: For every request, the web server forks a new process, executes the script, and kills the process. Very slow for high traffic.
>
> **FastCGI (modern)**: The application server (PHP-FPM) runs **persistently** as a pool of worker processes. The web server (NGINX) sends requests to these long-running workers over a socket. No fork/kill overhead. Much faster.
>
> In our `nginx.conf`: `fastcgi_pass wordpress:9000;` tells NGINX to forward PHP requests to the WordPress container on port 9000.

### Q: Why `listen = 9000` in `www.conf`?
> By default on Linux, PHP-FPM listens on a **UNIX domain socket** (`/run/php/php8.2-fpm.sock`). UNIX sockets are files on the filesystem — they only work when both processes share the same filesystem (same machine/container).
>
> Since NGINX is in a **separate container** (separate filesystem, separate network namespace), it cannot access a UNIX socket inside the WordPress container. Setting `listen = 9000` makes PHP-FPM listen on a **TCP socket** that's reachable across the Docker network.

### Q: What is `clear_env = no` in `www.conf`?
> By default, PHP-FPM **strips all environment variables** from its worker processes for security. Setting `clear_env = no` preserves Docker environment variables (like `DOMAIN_NAME`, `MYSQL_DATABASE`, `MYSQL_USER`) so that WordPress setup and WP-CLI commands can access them at runtime.

### Q: What is WP-CLI?
> WP-CLI (WordPress Command Line Interface) is the official command-line tool for managing WordPress. Instead of using the browser-based setup wizard, we use commands like:
> - `wp core download` — downloads WordPress files
> - `wp config create` — generates `wp-config.php` with database credentials
> - `wp core install` — configures the site (title, admin user, URL)
> - `wp user create` — creates additional users
> - `wp plugin install` — installs plugins (like redis-cache)
>
> This lets us **fully automate** WordPress setup in our entrypoint script.

### Q: How were the two WordPress users created?
> Automatically by `wp_setup.sh` during the initial boot:
> 1. `wp core install --admin_user="nakhalil_master"` — creates the administrator.
> 2. `wp user create "student_user" ... --role=author` — creates a second regular user.
> Verify: `docker exec wordpress wp user list --allow-root`

---

## Section 7: MariaDB & Its Volume

> **Eval sheet**: *"Ensure that there is a Dockerfile. Ensure that there is no NGINX in the Dockerfile. Ensure that there is a Volume (run 'docker volume ls' then 'docker volume inspect <volume name>' — verify path contains '/home/login/data'). The evaluated learner must be able to explain how to login into the database. Verify that the database is not empty."*

### Demonstration:
```bash
# Verify no NGINX:
docker exec mariadb which nginx
# Expected: not found

# Verify volume:
docker volume inspect srcs_mariadb_vol
# Look for: "device": "/home/nakhalil/data/mariadb"
```

### Q: How to log into the database?
```bash
# Login as the regular database user:
docker exec -it mariadb mariadb -u nakhalil -p"$(cat secrets/db_password.txt)" wordpress_db

# Once inside, verify the database is not empty:
SHOW TABLES;
# Shows: wp_posts, wp_users, wp_options, wp_comments, wp_links, etc.

# Verify actual data:
SELECT ID, post_title FROM wp_posts LIMIT 5;
```

### Q: Security Check — Can root log in with no password?
```bash
docker exec -it mariadb mariadb -u root
# Expected: ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: NO)
```
> `init_db.sh` explicitly secures root: `ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';`

### Q: What is MariaDB?
> MariaDB is a **relational database management system (RDBMS)** — a community-developed fork of MySQL created in 2009 by MySQL's original creator after Oracle acquired MySQL. It is wire-protocol compatible with MySQL (same port 3306, same SQL syntax, same client tools like `mariadb-admin`), but is fully open-source.
>
> In our project, MariaDB stores all WordPress data: posts, pages, comments, user accounts, site settings, and plugin configuration.

### Q: Why does `50-server.cnf` include `skip-name-resolve`?
> By default, MariaDB performs a **reverse DNS lookup** on every incoming TCP connection to resolve the connecting client's hostname. In Docker networks, container bridge IPs (like `172.20.0.5`) typically don't have reverse DNS PTR records. MariaDB would pause for a timeout on every connection, then reject it with `Error 1130: Host is not allowed to connect`.
>
> `skip-name-resolve` forces MariaDB to authenticate purely via IP address, eliminating connection hangs.

### Q: What does `bind-address = 0.0.0.0` do?
> By default, MariaDB binds to `127.0.0.1` (localhost only) — only processes on the same machine can connect. Since WordPress runs in a **separate container** (a different network namespace with a different IP), we set `bind-address = 0.0.0.0` so MariaDB accepts connections from any IP on the Docker bridge network.
>
> **Is this safe?** Yes — because MariaDB's port 3306 is only `expose`d (internal to Docker network), not `ports`-published to the host. Only containers on `inception_net` can reach it.

---

## Section 8: Persistence!

> **Eval sheet**: *"Reboot the virtual machine. Once it has restarted, launch docker compose again. Verify that everything is functional, and that both WordPress and MariaDB are still configured. The changes you made previously should still be here."*

### Q: How does persistent data survive when containers are ephemeral?
> Containers write changes to a temporary **writable layer** that is deleted when the container is removed. Any data stored only inside the container (not in a volume) is lost forever.
>
> Our project uses **Docker Named Volumes** backed by host directories:
> - `mariadb_vol` → `/home/nakhalil/data/mariadb` → mounted at `/var/lib/mysql` in the container
> - `wordpress_vol` → `/home/nakhalil/data/wordpress` → mounted at `/var/www/html` in the container
>
> When MariaDB writes a table or WordPress saves a post, the bytes are written directly to the **host machine's hard disk** at `/home/nakhalil/data/`. When the container is removed and recreated, Docker mounts the same host directory again — all data is intact.

### Q: Explain the Named Volume vs Bind Mount paradox and how it's solved.
> The subject has two seemingly contradictory requirements:
> 1. **Rule A**: *"You must use Docker named volumes. Bind mounts are not allowed."*
> 2. **Rule B**: *"Both named volumes must store data inside `/home/login/data` on the host."*
>
> **Why naive approaches fail:**
> - **Simple bind mount** (`- /home/nakhalil/data/mariadb:/var/lib/mysql` under the service):
>   This works, but it's NOT a Docker named volume. `docker volume ls` shows nothing → evaluation fails.
> - **Standard named volume** (plain `volumes: mariadb_vol:` at the bottom):
>   Docker stores data in `/var/lib/docker/volumes/mariadb_vol/_data/`. The inspect output doesn't contain `/home/nakhalil/data/` → evaluation fails.
>
> **Our solution — Named Volume with `driver_opts`**:
> ```yaml
> volumes:
>   mariadb_vol:
>     driver: local
>     driver_opts:
>       type: none
>       o: bind
>       device: /home/nakhalil/data/mariadb
> ```
> This creates a **real Docker Named Volume** (visible in `docker volume ls`, manageable via the Docker Volume API), but tells Docker's `local` driver to use a specific host path as the storage backend. Running `docker volume inspect srcs_mariadb_vol` shows both the volume name AND the `/home/nakhalil/data/` path.

### The Reboot Test:
1. Make a visible change (e.g., publish a post or add a comment).
2. `sudo reboot`
3. After reboot: `cd ~/inception && make up`
4. Open `https://nakhalil.42.fr` — site loads with all data intact.

---

## Section 9: Configuration Modification

> **Eval sheet**: *"The reviewer must ask the evaluated person to modify the configuration of one of the services (for example by changing the port it is using). The reviewer is free to choose which service and which new port. After the change, the evaluated person must rebuild and restart the project. The service must remain accessible and functional."*

### Key principle:
When changing a port, you update it in **two places**:
1. **Where the service listens** (its own config file).
2. **Where other services connect to it** (the client's config).

Then rebuild: `make re`

### Example: Change WordPress PHP-FPM port from 9000 to 9001

| Step | File | Change |
|---|---|---|
| 1 | `srcs/requirements/wordpress/conf/www.conf` | `listen = 9000` → `listen = 9001` |
| 2 | `srcs/requirements/nginx/conf/nginx.conf` | `fastcgi_pass wordpress:9000;` → `fastcgi_pass wordpress:9001;` |
| 3 | Terminal | `make re` |

### Quick reference for all services:

| Service | Files to modify |
|---|---|
| **NGINX port** (443 → 4443) | `nginx.conf`: `listen 4443 ssl;` + `docker-compose.yml`: `ports: "4443:4443"` |
| **MariaDB port** (3306 → 3307) | `50-server.cnf`: `port = 3307` + `wp_setup.sh`: `--dbhost="mariadb:3307"` + `docker-compose.yml`: `expose: ["3307"]` |
| **WordPress/PHP-FPM** (9000 → 9001) | `www.conf`: `listen = 9001` + `nginx.conf`: `fastcgi_pass wordpress:9001;` |
| **Redis** (6379 → 6380) | `redis.conf`: `port 6380` + `wp_setup.sh`: `WP_REDIS_PORT "6380"` |

---

## Section 10: Docker Secrets vs Environment Variables

### Q: Why use Docker Secrets instead of environment variables for passwords?
> | | Environment Variables (`.env`) | Docker Secrets (`/run/secrets/`) |
> |---|---|---|
> | **Visibility** | Visible in `docker inspect <container>` | NOT visible in `docker inspect` |
> | **Storage** | Passed as plain-text process environment | Mounted as in-memory files on **tmpfs** (RAM) |
> | **Logging** | Can leak in crash dumps, debug logs | Never written to disk or logs |
> | **Process access** | Readable via `/proc/<pid>/environ` by any process in the container | Only accessible by reading the file explicitly |
> | **Git safety** | `.env` can accidentally be committed | `secrets/` directory is gitignored |
>
> **What's in `.env`** (non-sensitive, OK in Git): `DOMAIN_NAME`, `MYSQL_USER`, `MYSQL_DATABASE`, `WP_ADMIN_USER`, `WP_ADMIN_EMAIL`, `WP_TITLE`, `FTP_USER`, `FTP_PASV_ADDRESS`.
>
> **What's in `secrets/`** (sensitive, NOT in Git): `db_password.txt`, `db_root_password.txt`, `wp_admin_password.txt`, `wp_user_password.txt`, `ftp_password.txt`.

### Q: How does your code read Docker Secrets?
> In the entrypoint scripts:
> ```bash
> MYSQL_PASSWORD=$(cat /run/secrets/db_password)
> WP_ADMIN_PASSWORD=$(cat /run/secrets/wp_admin_password)
> ```
> `cat` reads the secret file from the tmpfs mount. The password exists as a shell variable only during the setup phase. After `exec <daemon>` replaces the shell, the variable is gone.

### Q: How are secrets defined in docker-compose.yml?
> At the bottom of `docker-compose.yml`:
> ```yaml
> secrets:
>   db_password:
>     file: ../secrets/db_password.txt
> ```
> Each service declares which secrets it needs:
> ```yaml
> mariadb:
>   secrets: [ db_password, db_root_password ]
> ```
> Docker mounts the file content into the container at `/run/secrets/<secret_name>`.

---

## Section 11: PID 1, Process Management & Signals

### Q: What is PID 1 and why is it critical in Docker?
> PID 1 is the **first process** launched inside a container's PID namespace. On a physical Linux machine, PID 1 is `systemd` or `init`. In Docker, PID 1 is whatever your ENTRYPOINT runs.
>
> **Why PID 1 is special**:
>
> 1. **Signal handling**: When you run `docker stop`, Docker sends `SIGTERM` to **PID 1 only**. PID 1 must handle this signal to gracefully shut down — flush database buffers, close file handles, save state. If PID 1 ignores `SIGTERM`, Docker waits 10 seconds, then sends `SIGKILL` — an instant, ungraceful kill that can corrupt databases and leave files in an inconsistent state.
>
> 2. **Zombie reaping**: In Linux, when a child process finishes, it becomes a "zombie" — a dead process still occupying an entry in the process table, waiting for its parent to read its exit code. PID 1 has the special responsibility of adopting and reaping orphaned child processes. If PID 1 doesn't do this, zombie processes accumulate and eventually exhaust the process table.
>
> 3. **Container lifecycle**: Docker considers the container "running" as long as PID 1 is alive. If PID 1 exits, Docker stops the container. That's why daemons must run in the **foreground** — if they fork into the background, the original process (PID 1) exits and Docker shuts down the container.

### Q: How do you guarantee the daemon runs as PID 1?
> Every entrypoint script ends with `exec`:
> ```bash
> exec nginx -g "daemon off;"
> exec php-fpm8.2 -F
> exec mysqld_safe --user=mysql
> exec vsftpd /etc/vsftpd.conf
> ```
> The `exec` builtin **replaces** the current shell process with the specified command. The shell ceases to exist. The daemon inherits the same PID (PID 1) that the shell had.
>
> **Without `exec`**: The shell remains as PID 1, launches the daemon as a child process (PID 2). `docker stop` sends `SIGTERM` to the shell (PID 1), which may not forward it to the daemon. The daemon doesn't get a chance to shut down gracefully.

### Q: Why `daemon off;` and `-F`?
> - `nginx -g "daemon off;"` — Tells NGINX to stay in the **foreground**. By default, NGINX forks a master process into the background and the parent exits. In Docker, if PID 1 exits, the container stops.
> - `php-fpm8.2 -F` — The `-F` flag means "force foreground." Same reason.
> - `mysqld_safe` — Already runs in the foreground by design.

---

## Section 12: The Makefile & Orchestration Rules

### Q: Walk through the Makefile rules and their purpose.

| Target | What it does | When to use |
| :--- | :--- | :--- |
| `make all` | Creates data dirs, builds all images, starts all containers | First time setup or after `fclean` |
| `make build` | `mkdir -p` data dirs + `docker compose build` | When you've changed a Dockerfile |
| `make up` | `docker compose up -d` | Start containers (images already built) |
| `make down` | `docker compose down` | Stop + remove containers/network (data preserved) |
| `make stop` | `docker compose stop` | Pause containers without removing them |
| `make start` | `docker compose start` | Resume paused containers |
| `make status` | `docker compose ps` | Check container status |
| `make logs` | `docker compose logs -f` | Follow real-time logs |
| `make clean` | `down` + `docker system prune -f` | Clean stopped containers + build cache |
| `make fclean` | `down -v --rmi all` + `rm -rf /home/nakhalil/data` | **Nuclear wipe**: everything deleted |
| `make re` | `fclean` then `all` | Full rebuild from scratch |

### Q: Why `sudo mkdir -p` in the build target?
> The data directories (`/home/nakhalil/data/mariadb`, `/home/nakhalil/data/wordpress`) must exist on the host **before** Docker Compose creates the named volumes with `driver_opts`. If the directories don't exist, volume creation fails. `sudo` is needed because `/home/nakhalil/` may have restricted permissions.

### Q: What is `restart: always`?
> This Docker Compose directive tells Docker to automatically restart the container if it crashes or if the Docker daemon restarts (e.g., after a system reboot). The container will keep restarting until you explicitly stop it with `docker stop` or `docker compose down`.

### Q: What is `depends_on`?
> `depends_on` controls **startup order**. In our config:
> ```yaml
> wordpress:
>   depends_on: [ mariadb, redis ]
> ```
> Docker Compose starts MariaDB and Redis **before** WordPress. However, `depends_on` only waits for the container to **start** — not for the service inside to be **ready**. That's why `wp_setup.sh` has a `until mariadb-admin ping` loop to wait for MariaDB to actually accept connections.

---

## Section 13: Bonus Services

> **Eval sheet**: *"A Dockerfile must be written for each additional service. Each service will run inside its own container. Bonus part only if the mandatory part has been completed entirely and perfectly. Add 1 point per bonus authorized in the subject."*

### 1. Redis Cache
- **What it is**: Redis is an **in-memory key-value data store**. In our project, it acts as an object cache for WordPress.
- **How it works**: When a user visits a WordPress page, PHP executes SQL queries against MariaDB to build the page. Redis caches the results in RAM. On subsequent visits, WordPress reads from Redis (microseconds) instead of querying MariaDB (milliseconds), dramatically reducing load and speeding up page delivery.
- **How it was set up**: `wp_setup.sh` installs the `redis-cache` plugin and configures `WP_REDIS_HOST=redis`, `WP_REDIS_PORT=6379`.
- **Test**:
  ```bash
  docker exec redis redis-cli PING                     # returns PONG
  docker exec redis redis-cli DBSIZE                   # returns active keys count
  docker exec wordpress wp redis status --allow-root   # shows "Status: Connected"
  ```

### 2. FTP Server
- **What it is**: `vsftpd` (Very Secure FTP Daemon) running in its own container.
- **How it works**: The FTP container mounts the same `wordpress_vol` volume as WordPress, pointing to `/var/www/html`. This allows uploading/downloading WordPress files (themes, plugins, media) via the FTP protocol without needing SSH access.
- **Test**:
  ```bash
  ftp localhost 21
  # User: ftpuser
  # Password: (from secrets/ftp_password.txt)
  ftp> ls        # Should list WordPress files
  ftp> quit
  ```

### 3. Static Website (No PHP)
- **What it is**: A showcase/portfolio page written in pure HTML/CSS.
- **Compliance**: The subject mandates *"in the language of your choice except PHP."* We use **Python 3** (`python3 -m http.server 3000`) to serve the files — no PHP installed.
- **How it works**: NGINX reverse-proxies requests matching `/static/` to `static_site:3000`.
- **Test**:
  - Open `https://nakhalil.42.fr/static/` in a browser.
  - Show `srcs/requirements/bonus/static_site/Dockerfile` to prove no PHP.

### 4. Adminer
- **What it is**: A lightweight, **single-file** database administration web interface (alternative to phpMyAdmin).
- **How it works**: Runs PHP's built-in web server on port 8080 inside its own container. NGINX reverse-proxies `/adminer` to it.
- **Test**:
  - Open `https://nakhalil.42.fr/adminer` in a browser.
  - Log in with: System=MySQL, Server=`mariadb`, Username=`nakhalil`, Password=(from `secrets/db_password.txt`), Database=`wordpress_db`.

### 5. Service of Choice: Google cAdvisor
> **Eval sheet**: *"The evaluated student has to give you a simple explanation about how it works and why they think it is useful."*

- **Your explanation**:
  > *"cAdvisor (Container Advisor) is an open-source container resource monitor by Google. It reads real-time statistics from Linux kernel cgroups and /sys to monitor CPU usage, memory consumption, network throughput, and disk I/O for each individual container. It's useful because in a multi-container architecture like Inception, you need visibility into which container is consuming the most resources, whether any container is leaking memory, or if a service is CPU-bottlenecked. It provides a web dashboard to visualize all of this."*
- **Why the volume mounts** (all `:ro` = read-only for security):
  - `/:/rootfs:ro` — Host filesystem (disk usage stats)
  - `/var/run:/var/run:ro` — Running process info
  - `/sys:/sys:ro` — Kernel/cgroup metrics
  - `/var/lib/docker/:/var/lib/docker:ro` — Docker container metadata
  - `/dev/disk/:/dev/disk:ro` — Disk device info
- **Test**: Open `http://localhost:8080` → see real-time graphs for all containers.
