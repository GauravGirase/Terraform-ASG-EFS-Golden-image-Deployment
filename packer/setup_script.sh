#!/bin/bash

# Install Nginx and EFS utils
sudo amazon-linux-extras enable nginx1
sudo yum install -y nginx amazon-efs-utils
sudo yum install -y python3-botocore

# Enable Nginx service
sudo systemctl enable nginx

sudo mkdir -p /mnt/efs/current
sudo mkdir -p /etc/nginx/conf.d/

# Write new webapp config
cat << 'EOF' | sudo tee /etc/nginx/conf.d/webapp.conf
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /mnt/efs/current;
    index index.html;

    location / {
        try_files $uri $uri/index.html =404;
    }
}
EOF
