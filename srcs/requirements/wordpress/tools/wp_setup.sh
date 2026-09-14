#!/bin/bash
set -e

MYSQL_PASSWORD=$(cat /run/secrets/db_password)
WP_ADMIN_PASSWORD=$(cat /run/secrets/wp_admin_password)
WP_USER_PASSWORD=$(cat /run/secrets/wp_user_password)

mkdir -p /run/php /var/www/html
chown -R www-data:www-data /var/www/html
chmod -R 775 /var/www/html
echo "Waiting for MariaDB connection..."
until mariadb-admin -h"mariadb" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" --skip-ssl ping >/dev/null 2>&1; do
    echo "MariaDB is not ready yet, retrying in 2 seconds..."
    sleep 2
done
echo "Connected to MariaDB successfully!"

if [ ! -f /var/www/html/wp-config.php ]; then
    wp core download --path=/var/www/html --allow-root --force
    
    wp config create --path=/var/www/html --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" --dbpass="${MYSQL_PASSWORD}" \
        --dbhost="mariadb:3306" --allow-root
        
    wp core install --path=/var/www/html --url="https://${DOMAIN_NAME}" \
        --title="${WP_TITLE}" --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" --admin_email="${WP_ADMIN_EMAIL}" \
        --allow-root
        
    wp user create "${WP_USER}" "${WP_USER_EMAIL}" --user_pass="${WP_USER_PASSWORD}" \
        --role=author --path=/var/www/html --allow-root

    wp plugin install redis-cache --activate --path=/var/www/html --allow-root
    wp config set WP_REDIS_HOST "redis" --path=/var/www/html --allow-root
    wp config set WP_REDIS_PORT "6379" --raw --path=/var/www/html --allow-root
    wp config set WP_CACHE true --raw --path=/var/www/html --allow-root
    wp redis enable --path=/var/www/html --allow-root || true
fi

chown -R www-data:www-data /var/www/html
chmod -R 775 /var/www/html
exec php-fpm8.2 -F