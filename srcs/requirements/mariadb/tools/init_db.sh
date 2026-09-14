#!/bin/bash
set -e

# Read passwords from Docker Secrets
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
MYSQL_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)

mkdir -p /run/mysqld /var/lib/mysql /var/log/mysql
chown -R mysql:mysql /run/mysqld /var/lib/mysql /var/log/mysql

if [ ! -d "/var/lib/mysql/mysql" ]; then
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql > /dev/null
fi

if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then
    mysqld_safe --skip-networking --socket=/run/mysqld/mysqld.sock &
    pid="$!"

    for i in $(seq 30 -1 0); do
        if mariadb-admin ping --socket=/run/mysqld/mysqld.sock --silent; then break; fi
        sleep 1
    done

    mariadb -u root --socket=/run/mysqld/mysqld.sock <<-EOF
    CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
    CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
    ALTER USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
    GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
    CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
    ALTER USER '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
    GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'localhost';
    ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
    FLUSH PRIVILEGES;
EOF

    mariadb-admin -u root -p"${MYSQL_ROOT_PASSWORD}" --socket=/run/mysqld/mysqld.sock shutdown
    wait "$pid"
fi

exec mysqld_safe --user=mysql