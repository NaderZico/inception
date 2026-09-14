#!/bin/bash
set -e

echo "=========================================="
echo "  42 Inception Automated VM Setup Script  "
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[1/6] Installing dependencies..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg make git

echo "[2/6] Setting up Docker repository..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[3/6] Adding user '$USER' to docker group..."
sudo usermod -aG docker "$USER"

echo "[4/6] Configuring /etc/hosts..."
if ! grep -q "nakhalil.42.fr" /etc/hosts; then
  sudo sh -c 'echo "127.0.0.1 nakhalil.42.fr" >> /etc/hosts'
  echo "--> Added 127.0.0.1 nakhalil.42.fr to /etc/hosts"
else
  echo "--> nakhalil.42.fr already present in /etc/hosts"
fi

echo "[5/6] Creating secrets and usernames..."
mkdir -p secrets

# Passwords
echo "password123" > secrets/db_password.txt
echo "root123"     > secrets/db_root_password.txt
echo "password123" > secrets/wp_admin_password.txt
echo "password123" > secrets/wp_user_password.txt
echo "password123" > secrets/ftp_password.txt

# Usernames
echo "nakhalil"        > secrets/db_user.txt
echo "nakhalil_master" > secrets/wp_admin_user.txt
echo "student_user"    > secrets/wp_user.txt
echo "ftpuser"         > secrets/ftp_user.txt

# Complete credentials file (as shown in subject example)
cat << 'EOF' > secrets/credentials.txt
=== INCEPTION CREDENTIALS ===

WordPress (https://nakhalil.42.fr):
  Admin:   nakhalil_master / password123
  Author:  student_user / password123

MariaDB / Adminer (https://nakhalil.42.fr/adminer):
  Server:   mariadb
  Database: wordpress_db
  User:     nakhalil / password123
  Root:     root / root123

FTP Server (Port 21):
  User:     ftpuser / password123

Static Site:
  URL:      https://nakhalil.42.fr/static/

cAdvisor Monitoring:
  URL:      http://localhost:8080
EOF

chmod 600 secrets/*
echo "--> Passwords, usernames, and credentials.txt created in secrets/ (chmod 600)."

echo "[6/6] Building and starting Inception..."
sg docker -c "make all"

echo "Waiting for WordPress to finish downloading and initializing database..."
for i in {1..30}; do
  if [ -f /home/nakhalil/data/wordpress/wp-config.php ]; then
    echo "--> WordPress setup completed successfully!"
    break
  fi
  sleep 2
done

echo "=========================================="
echo "  Inception is fully built and running!   "
echo ""
echo "  Credentials & URLs:                     "
echo "  WordPress:   https://nakhalil.42.fr     "
echo "    Admin:     nakhalil_master / password123"
echo "    Author:    student_user / password123 "
echo ""
echo "  Adminer:     https://nakhalil.42.fr/adminer"
echo "    Server:    mariadb                    "
echo "    User:      nakhalil / password123     "
echo ""
echo "  Static Site: https://nakhalil.42.fr/static/"
echo "  cAdvisor:    http://localhost:8080      "
echo "  FTP:         ftpuser / password123      "
echo "=========================================="
