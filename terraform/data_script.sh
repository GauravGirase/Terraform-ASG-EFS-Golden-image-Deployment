#!/bin/bash
exec > >(tee -a /var/log/user-data.log) 2>&1
set -euxo pipefail

echo "Set the ENV for efs"
# Persist EFS info (from Terraform vars)
cat <<EOT >/etc/efs.env
efs_id: ${efs_id}
efs_dns: ${efs_dns}
EOT
echo "ENV set for efs successfully"

# Install Ansible
echo "Installing ansible"
sudo yum install -y amazon-linux-extras
sudo amazon-linux-extras enable ansible2 nginx1
sudo yum install -y ansible git
echo "Installing ansible is done"

# Create a systemd service for ansible-pull
cat <<EOF >/etc/systemd/system/ansible-pull.service
[Unit]
Description=Run Ansible Pull for EFS setup
After=network-online.target remote-fs.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/ansible-pull -U https://github.com/GauravGirase/Terraform-ASG-EFS-Golden-image-Deployment.git playbooks/efs.yml
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable & start the service
systemctl daemon-reload
systemctl enable ansible-pull.service
systemctl start ansible-pull.service

# Install nginx
echo "Installing nginx"
sudo yum install -y python3- || true
sudo yum install -y nginx
echo "Installing nginx is done"

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

