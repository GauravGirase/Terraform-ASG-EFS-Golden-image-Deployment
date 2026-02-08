#!/bin/bash
set -euxo pipefail

# Persist EFS info (from Terraform vars)
cat <<EOT >/etc/efs.env
efs_id: ${efs_id}
efs_dns: ${efs_dns}
EOT

# Install Ansible
yum install -y amazon-linux-extras
amazon-linux-extras enable ansible2
yum install -y ansible git

# Run Ansible (pull model)
ansible-pull -U https://github.com/GauravGirase/Terraform-ASG-EFS-Golden-image-Deployment.git playbooks/efs.yml
