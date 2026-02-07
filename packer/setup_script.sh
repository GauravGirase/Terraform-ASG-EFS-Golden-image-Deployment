#!/bin/bash

# Install Nginx and EFS utils
sudo yum install -y nginx amazon-efs-utils

# Enable Nginx service
sudo systemctl enable nginx

# Remove default config
sudo rm -f /etc/nginx/conf.d/default.conf

# Write new webapp config
cat << 'EOF' | sudo tee /etc/nginx/conf.d/webapp.conf
server {
    listen 80;
    root /mnt/efs/current;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
