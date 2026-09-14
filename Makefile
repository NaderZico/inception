NAME = inception
COMPOSE_FILE = srcs/docker-compose.yml
DATA_DIR = /home/nakhalil/data
MARIADB_DIR = $(DATA_DIR)/mariadb
WORDPRESS_DIR = $(DATA_DIR)/wordpress

.PHONY: all build up down stop start clean fclean re status logs mariadb wordpress nginx redis adminer static_site cadvisor ftp
all: build up

build:
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