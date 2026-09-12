*This project has been created as part of the 42 curriculum by nakhalil.*

## Description
Inception is a System Administration project that introduces Docker and docker-compose. The goal is to set up a small infrastructure consisting of different services (NGINX, WordPress, MariaDB, and several bonuses) running in dedicated containers on a virtual machine. It aims to teach containerization, networking, volumes, and security best practices.

## Instructions
1. **Compilation/Build:** Run `make all` from the project root. This command uses `docker-compose` to build the required Docker images locally and start all the containers.
2. **Installation/Prerequisites:** Ensure Docker and Docker Compose are installed. You must map `127.0.0.1 nakhalil.42.fr` in `/etc/hosts` and place the required passwords in the `secrets/` directory (see `DEV_DOC.md` for exact paths).
3. **Execution/Management:** Use `make stop` to pause, `make start` to resume, `make down` to gracefully shut down the network, or `make fclean` to wipe the system of all images, containers, and data.

## Resources
- [Docker Documentation](https://docs.docker.com/)
- [NGINX Documentation](https://nginx.org/en/docs/)
- [WordPress Documentation](https://wordpress.org/documentation/)
- [MariaDB Documentation](https://mariadb.com/kb/en/)
- **AI Usage:** AI was used to help generate the configuration files, debug MariaDB upgrade issues, and structure this documentation.

## Project description
This project utilizes Docker to containerize all services, ensuring they run consistently across any environment. The infrastructure includes NGINX (serving HTTPS), WordPress (with PHP-FPM), MariaDB (database), Redis (caching), Adminer (database management), a static HTML site, and cAdvisor (monitoring).

**Main Design Choices:**
- **Debian Bookworm** is used as the base image for all containers to satisfy the penultimate stable version requirement.
- **Custom Entrypoint Scripts** (`init_db.sh`, `wp_setup.sh`) configure the databases and services at runtime dynamically.

### Comparisons

**Virtual Machines vs Docker:**
Virtual machines emulate an entire hardware stack and run a full guest operating system, making them resource-heavy. Docker containers share the host system's kernel and only package the application and its dependencies, making them lightweight, faster to start, and more efficient.

**Secrets vs Environment Variables:**
Environment variables are passed to containers at runtime but can be easily exposed if the container is inspected (`docker inspect`) or if the application crashes. Docker Secrets provide a secure mechanism for sensitive data (like passwords) by mounting them as temporary, in-memory files (`/run/secrets/`) that are never stored on disk or exposed in environment variables.

**Docker Network vs Host Network:**
Using the host network directly exposes container ports to the host's network stack, which can lead to port conflicts and security risks. A custom Docker bridge network (`inception_net`) isolates the containers, allowing them to communicate securely with each other using internal DNS (container names) while only exposing explicitly published ports (e.g., 443) to the outside world.

**Docker Volumes vs Bind Mounts:**
Bind mounts rely on the host machine's specific directory structure, which can lead to permission issues and lacks portability. Docker Volumes are managed entirely by Docker, making them independent of the host filesystem structure, easier to back up, and more secure for persistent storage like databases.
