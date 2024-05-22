#!/bin/bash

# Update system and install necessary packages
echo "Updating system and installing prerequisites..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y curl libffi-dev libssl-dev python3 python3-pip
sudo apt-get remove -y python-configparser

# Check if Docker is installed and install if not
if ! [ -x "$(command -v docker)" ]; then
    echo "Installing Docker..."
    curl -sSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    newgrp docker
else
    echo "Docker already installed"
fi

# Install Docker Compose as a standalone binary
echo "Installing Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/download/v2.5.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install Avahi daemon
echo "Installing Avahi daemon..."
sudo apt-get install -y avahi-daemon libnss-mdns
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon

# Set the hostname permanently
echo "Setting hostname to 'nextcloud'..."
sudo hostnamectl set-hostname nextcloud
# Update /etc/hosts for local resolution
sudo sed -i 's/127.0.1.1 .*/127.0.1.1 nextcloud/g' /etc/hosts

# Create directories for Nextcloud and Nginx configuration
echo "Creating directories and configuration files..."
mkdir -p nextcloud-docker
cd nextcloud-docker

# Function to prompt for user input
prompt() {
    read -p "$1" input
    echo $input
}

# Collecting environment variables
MYSQL_ROOT_PASSWORD=$(prompt "Enter MariaDB root password: ")
MYSQL_PASSWORD=$(prompt "Enter Nextcloud DB password: ")
MYSQL_DATABASE=$(prompt "Enter Nextcloud database name, default 'nextcloud': ")
MYSQL_USER=$(prompt "Enter Nextcloud database user, default 'nextcloud': ")

# Set default values if not provided
MYSQL_DATABASE=${MYSQL_DATABASE:-nextcloud}
MYSQL_USER=${MYSQL_USER:-nextcloud}

# Create SSL certificates for Nginx
echo "Generating SSL certificates..."
mkdir -p nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout nginx/ssl/nextcloud.local.key \
    -out nginx/ssl/nextcloud.local.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=nextcloud.local"

# Create Docker Compose file
cat <<EOF > docker-compose.yml
version: '3.7'

services:
  db:
    image: yobasystems/alpine-mariadb
    container_name: nextcloud-mariadb
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW
    restart: always
    volumes:
      - db:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
      - MYSQL_PASSWORD=$MYSQL_PASSWORD
      - MYSQL_DATABASE=$MYSQL_DATABASE
      - MYSQL_USER=$MYSQL_USER
  app:
    image: nextcloud
    container_name: nextcloud-app
    ports:
      - 8080:80
    links:
      - db
    volumes:
      - nextcloud:/var/www/html
    restart: always

  web:
    image: nginx
    container_name: nextcloud-nginx
    ports:
      - 80:80
      - 443:443
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - nextcloud:/var/www/html:ro
    links:
      - app
    restart: always

volumes:
  db:
  nextcloud:
EOF

# Create Nginx configuration file
cat <<EOF > nginx.conf
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    access_log /var/log/nginx/access.log;
    keepalive_timeout 65;
    server {
        listen 80;
        listen 443 ssl;
        server_name _;
        root /var/www/html;

        ssl_certificate /etc/nginx/ssl/nextcloud.local.crt;
        ssl_certificate_key /etc/nginx/ssl/nextcloud.local.key;

        location / {
            proxy_pass http://app:80;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_redirect off;
        }
    }
}
EOF

# Start Docker containers
echo "Starting Docker containers..."
docker-compose up -d

IP_ADDRESS=$(hostname -I | cut -d' ' -f1)
echo "Setup completed successfully. Nextcloud should be accessible via $IP_ADDRESS and at http://nextcloud.local"
