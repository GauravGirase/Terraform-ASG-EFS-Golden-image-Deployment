#!/bin/bash
set -euxo pipefail

# Persist EFS info (from Terraform vars)
cat <<EOT >/etc/efs.env
efs_id: ${efs_id}
efs_dns: ${efs_dns}
EOT

# Install Ansible
sudo yum install -y amazon-linux-extras
sudo amazon-linux-extras enable ansible2
sudo yum install -y ansible git

# Install nginx
sudo amazon-linux-extras enable nginx1
sudo yum install -y python3-botocore
sudo yum install -y nginx

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

# Run Ansible (pull model)
sudo ansible-pull -U https://github.com/GauravGirase/Terraform-ASG-EFS-Golden-image-Deployment.git playbooks/efs.yml
