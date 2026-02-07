packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.2.0"
    }
  }
}

source "amazon-ebs" "webapp" {
  region          = "ap-south-1"
  instance_type   = "t3.micro"
  ami_name        = "webapp-ami-{{timestamp}}"
  ssh_username    = "ec2-user"

  source_ami_filter {
    filters = {
      name                = "amzn2-ami-hvm-*-x86_64-gp2"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["amazon"]
    most_recent = true
  }
  
  tags = {
    App     = "webapp"
    Version = "{{timestamp}}"
    Env     = "prod"
  }
}

build {
  sources = ["source.amazon-ebs.webapp"]

  provisioner "shell" {
        inline = [
            "sudo yum install -y nginx amazon-efs-utils",

            "sudo systemctl enable nginx",
            
            "sudo rm -f /etc/nginx/conf.d/default.conf",

            "cat << 'EOF' | sudo tee /etc/nginx/conf.d/webapp.conf
              server {
                  listen 80;
                  root /mnt/efs/current;
                  index index.html;

                  location / {
                      try_files \\$uri \\$uri/ =404;
                  }
              }
              EOF
            "
        ]
    }
}
