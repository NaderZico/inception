USER ?= $(shell whoami)
NAME = inception
COMPOSE_FILE = srcs/docker-compose.yml
DATA_DIR = /home/nakhalil/data
MARIADB_DIR = $(DATA_DIR)/mariadb
WORDPRESS_DIR = $(DATA_DIR)/wordpress
SECRETS_DIR = secrets

.PHONY: all build up down stop start clean fclean re status logs secrets mariadb wordpress nginx redis adminer static_site cadvisor ftp
all: secrets build up

secrets:
	@mkdir -p $(SECRETS_DIR)
	@test -f $(SECRETS_DIR)/db_password.txt || openssl rand -base64 12 | tr -dc A-Za-z0-9 > $(SECRETS_DIR)/db_password.txt
	@test -f $(SECRETS_DIR)/db_root_password.txt || openssl rand -base64 12 | tr -dc A-Za-z0-9 > $(SECRETS_DIR)/db_root_password.txt
	@test -f $(SECRETS_DIR)/wp_admin_password.txt || openssl rand -base64 12 | tr -dc A-Za-z0-9 > $(SECRETS_DIR)/wp_admin_password.txt
	@test -f $(SECRETS_DIR)/wp_user_password.txt || openssl rand -base64 12 | tr -dc A-Za-z0-9 > $(SECRETS_DIR)/wp_user_password.txt
	@test -f $(SECRETS_DIR)/ftp_password.txt || openssl rand -base64 12 | tr -dc A-Za-z0-9 > $(SECRETS_DIR)/ftp_password.txt
	@test -f $(SECRETS_DIR)/credentials.txt || ( \
		echo "=== INCEPTION CREDENTIALS ==="; \
		echo ""; \
		echo "WordPress (https://nakhalil.42.fr):"; \
		echo "  Admin:   nakhalil_master / $$(cat $(SECRETS_DIR)/wp_admin_password.txt)"; \
		echo "  Author:  student_user / $$(cat $(SECRETS_DIR)/wp_user_password.txt)"; \
		echo ""; \
		echo "MariaDB / Adminer (https://nakhalil.42.fr/adminer):"; \
		echo "  Server:   mariadb"; \
		echo "  Database: wordpress_db"; \
		echo "  User:     nakhalil / $$(cat $(SECRETS_DIR)/db_password.txt)"; \
		echo "  Root:     root / $$(cat $(SECRETS_DIR)/db_root_password.txt)"; \
		echo ""; \
		echo "FTP Server (Port 21):"; \
		echo "  User:     ftpuser / $$(cat $(SECRETS_DIR)/ftp_password.txt)"; \
		echo ""; \
		echo "Static Site:"; \
		echo "  URL:      https://nakhalil.42.fr/static/"; \
		echo ""; \
		echo "cAdvisor Monitoring:"; \
		echo "  URL:      http://localhost:8080"; \
	) > $(SECRETS_DIR)/credentials.txt
	@chmod 600 $(SECRETS_DIR)/* 2>/dev/null || true

build: secrets
	@sudo mkdir -p $(MARIADB_DIR) $(WORDPRESS_DIR)
	@sudo chown -R $(USER):$(USER) $(DATA_DIR)
	@sudo chmod -R 775 $(DATA_DIR)
	@docker compose -f $(COMPOSE_FILE) build

up:
	@docker compose -f $(COMPOSE_FILE) up -d

down:
	@docker compose -f $(COMPOSE_FILE) down

stop:
	@docker compose -f $(COMPOSE_FILE) stop

start:
	@docker compose -f $(COMPOSE_FILE) start

status:
	@docker compose -f $(COMPOSE_FILE) ps

logs:
	@docker compose -f $(COMPOSE_FILE) logs -f

mariadb:
	@sudo mkdir -p $(MARIADB_DIR)
	@docker compose -f $(COMPOSE_FILE) up -d --build mariadb

wordpress:
	@sudo mkdir -p $(WORDPRESS_DIR)
	@docker compose -f $(COMPOSE_FILE) up -d --build wordpress

nginx:
	@docker compose -f $(COMPOSE_FILE) up -d --build nginx

redis:
	@docker compose -f $(COMPOSE_FILE) up -d --build redis

adminer:
	@docker compose -f $(COMPOSE_FILE) up -d --build adminer

static_site:
	@docker compose -f $(COMPOSE_FILE) up -d --build static_site

cadvisor:
	@docker compose -f $(COMPOSE_FILE) up -d --build cadvisor

ftp:
	@sudo mkdir -p $(WORDPRESS_DIR)
	@docker compose -f $(COMPOSE_FILE) up -d --build ftp

clean: down
	@docker system prune -f

fclean: down
	@docker compose -f $(COMPOSE_FILE) down -v --rmi all --remove-orphans 2>/dev/null || true
	@docker system prune -af --volumes 2>/dev/null || true
	@sudo rm -rf $(DATA_DIR) 2>/dev/null || rm -rf $(DATA_DIR) 2>/dev/null || true
	@echo "All containers, images, volumes, and persistent data have been purged."


re: fclean all