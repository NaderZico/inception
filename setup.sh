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

echo "[5/6] Creating secrets..."
mkdir -p secrets
[ ! -f secrets/db_password.txt ]      && echo "user_password123"    > secrets/db_password.txt
[ ! -f secrets/db_root_password.txt ] && echo "root_password123"    > secrets/db_root_password.txt
[ ! -f secrets/wp_admin_password.txt ]&& echo "master_password123"  > secrets/wp_admin_password.txt
[ ! -f secrets/wp_user_password.txt ] && echo "student_password123" > secrets/wp_user_password.txt
[ ! -f secrets/ftp_password.txt ]     && echo "ftp_password123"     > secrets/ftp_password.txt
chmod 600 secrets/*.txt
echo "--> Secrets created and secured with 600 permissions."

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
echo "  WordPress:   https://nakhalil.42.fr     "
echo "  Adminer:     https://nakhalil.42.fr/adminer"
echo "  Static Site: https://nakhalil.42.fr/static/"
echo "  cAdvisor:    http://localhost:8080      "
echo "=========================================="
