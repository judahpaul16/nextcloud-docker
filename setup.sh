#!/bin/bash

# Prompt for domain, email, and database details
echo "This script will setup NextCloud with Docker and Nginx on your server."
echo "You'll want to have a domain name pointing to your server's IP address if you haven't already."
read -p "Enter the domain name for your NextCloud NGINX configuration: " DOMAIN
read -p "Enter your email for SSL certificate registration: " EMAIL
read -p "Enter MariaDB root password: " MYSQL_ROOT_PASSWORD
read -p "Enter Nextcloud database password: " MYSQL_PASSWORD
read -p "Enter Nextcloud database name (default 'nextcloud'): " MYSQL_DATABASE
read -p "Enter Nextcloud database user (default 'nextcloud'): " MYSQL_USER

# Set default database name and user if not provided
MYSQL_DATABASE=${MYSQL_DATABASE:-nextcloud}
MYSQL_USER=${MYSQL_USER:-nextcloud}

# Update system and install necessary packages
echo "Updating system and installing prerequisites..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y curl libffi-dev libssl-dev python3 python3-pip nginx certbot python3-certbot-nginx

# Ensure Nginx is enabled and running
sudo systemctl enable nginx
sudo systemctl start nginx

# Check if Docker is installed and install if not
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -sSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    newgrp docker
else
    echo "Docker already installed."
fi

# Install Docker Compose
echo "Installing Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/download/v2.5.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Create directories for Nextcloud and configuration files
mkdir -p ~/nextcloud-docker && cd ~/nextcloud-docker

# Create Docker Compose file
cat <<EOF > docker-compose.yml
version: '3.7'
services:
  db:
    image: mariadb
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
    restart: always
    ports:
      - 8080:80
    volumes:
      - nextcloud:/var/www/html
volumes:
  db:
  nextcloud:
EOF

# Configure Nginx
sudo tee /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Install SSL certificate using Certbot
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $EMAIL --redirect

# Start Docker containers
echo "Starting Docker containers..."
docker-compose up -d

echo "Setup completed successfully. NextCloud is now available at https://$DOMAIN."
