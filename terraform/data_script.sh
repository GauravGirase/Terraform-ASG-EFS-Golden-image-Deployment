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
sudo yum install -y ansible git nginx
echo "Installing ansible,nginx is done"

echo "waiting for 120 sec to finish cloud init"
sleep 120

# Create a systemd service for ansible-pull
cat <<EOF >/etc/systemd/system/ansible-pull.service
[Unit]
Description=Run Ansible Pull for EFS setup
After=network-online.target remote-fs.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 30
ExecStartPre=/bin/bash -c 'for i in {1..30}; do nslookup github.com && break || sleep 10; done'
ExecStartPre=/bin/bash -c 'for i in {1..30}; do nslookup ${efs_dns} && break || sleep 10; done'
ExecStart=/usr/bin/ansible-pull -U https://github.com/GauravGirase/Terraform-ASG-EFS-Golden-image-Deployment.git playbooks/efs.yml
Environment=PATH=/usr/bin:/usr/local/bin
StandardOutput=journal
StandardError=journal
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable & start the service
systemctl daemon-reload
systemctl enable ansible-pull.service
systemctl start ansible-pull.service

