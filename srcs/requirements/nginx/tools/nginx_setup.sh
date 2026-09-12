#!/bin/bash
set -e

# Generate SSL Certificate dynamically using DOMAIN_NAME from .env
mkdir -p /etc/ssl/private /etc/ssl/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/nginx-selfsigned.key \
    -out /etc/ssl/certs/nginx-selfsigned.crt \
    -subj "/C=FR/ST=Paris/L=Paris/O=42/OU=Inception/CN=${DOMAIN_NAME}"

# Replace the DOMAIN_NAME placeholder in NGINX config with the actual domain name
sed -i "s/DOMAIN_NAME_PLACEHOLDER/${DOMAIN_NAME}/g" /etc/nginx/conf.d/default.conf

# Start NGINX
exec nginx -g "daemon off;"