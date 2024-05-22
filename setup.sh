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

# Install Docker Compose within a Python virtual environment
echo "Installing Docker Compose within a virtual environment..."
sudo apt-get install -y python3-venv
python3 -m venv ~/docker-compose-venv
source ~/docker-compose-venv/bin/activate
pip install docker-compose

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
        server_name _;
        root /var/www/html;

        location / {
            proxy_pass http://app:80;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
}
EOF

# Start Docker containers
echo "Starting Docker containers..."
docker-compose up -d

IP_ADDRESS=$(hostname -I | cut -d' ' -f1)
echo "Setup completed successfully. Nextcloud should be accessible via $IP_ADDRESS"
