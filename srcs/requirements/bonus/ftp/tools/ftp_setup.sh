#!/bin/bash
set -e

FTP_PASSWORD=$(cat /run/secrets/ftp_password)

if ! id -u "$FTP_USER" &>/dev/null; then
    # Create the user with /var/www/html as home directory
    useradd -m -d /var/www/html -s /bin/bash "$FTP_USER"
    echo "$FTP_USER:$FTP_PASSWORD" | chpasswd
    
    # We want FTP user to be able to modify www-data owned files
    usermod -aG www-data "$FTP_USER"
    
    # Fix ownership if needed
    chown -R $FTP_USER:www-data /var/www/html
fi

# Ensure empty dir exists for vsftpd chroot
mkdir -p /var/run/vsftpd/empty

# Inject the passive address from env (defaults to 127.0.0.1 for local use)
PASV_ADDR="${FTP_PASV_ADDRESS:-127.0.0.1}"
sed -i "s/PASV_ADDR_PLACEHOLDER/${PASV_ADDR}/g" /etc/vsftpd.conf

echo "Starting vsftpd..."
exec vsftpd /etc/vsftpd.conf
