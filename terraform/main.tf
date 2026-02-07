provider "aws" {
  region = "ap-south-1"
}

terraform {
  required_version = ">= 1.5"
}

# Networking (VPC + Subnets)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "prod-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}


# Security Groups
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Added for debugging purpose
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name   = "ec2-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Added for debugging purpose
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "efs_sg" {
  name   = "efs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  # Added for debugging purpose
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EFS (shared storage)
resource "aws_efs_file_system" "shared" {
  encrypted = true

  tags = {
    Name = "shared-efs"
  }
}

resource "aws_efs_mount_target" "a" {
  file_system_id  = aws_efs_file_system.shared.id
  subnet_id       = aws_subnet.public_a.id
  security_groups = [aws_security_group.efs_sg.id]
}

resource "aws_efs_mount_target" "b" {
  file_system_id  = aws_efs_file_system.shared.id
  subnet_id       = aws_subnet.public_b.id
  security_groups = [aws_security_group.efs_sg.id]
}


# Application Load Balancer
resource "aws_lb" "alb" {
  name               = "web-alb"
  load_balancer_type = "application"
  subnets            = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]
  security_groups = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

data "aws_ami" "latest_webapp" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "tag:App"
    values = ["webapp"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Launch Template + ASG
resource "aws_launch_template" "lt" {
  name_prefix   = "web-lt-"
  image_id      = data.aws_ami.latest_webapp.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = base64encode(<<EOF
        #!/bin/bash
        mount -t efs ${aws_efs_file_system.shared.id}:/ /mnt/efs

        mkdir -p /mnt/efs/releases/v1
        mkdir -p /mnt/efs/shared/uploads

        if [ ! -L /mnt/efs/current ]; then
        ln -s /mnt/efs/releases/v1 /mnt/efs/current
        fi

        echo "<h1>Version 1 - Production App</h1>" > /mnt/efs/releases/v1/index.html

        systemctl start nginx
        EOF
    )

    iam_instance_profile {
        name = aws_iam_instance_profile.ec2_profile.name
    }
}

resource "aws_autoscaling_group" "asg" {
  desired_capacity = 2
  max_size         = 3
  min_size         = 1

  vpc_zone_identifier = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.tg.arn]
}

# IAM Role + Instance Profile (Terraform)

resource "aws_iam_role" "ec2_role" {
  name = "prod-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach AWS-managed policies
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance Profile (this is what EC2 actually uses)
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "prod-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role" "lambda_role" {
  name = "deploy-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_asg" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
}


# Lambda + EFS configuration (Terraform)
# Create EFS access point
resource "aws_efs_access_point" "lambda_ap" {
  file_system_id = aws_efs_file_system.shared.id

  root_directory {
    path = "/"
  }

  posix_user {
    uid = 1000
    gid = 1000
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# Lambda function
resource "aws_lambda_function" "deploy" {
  function_name = "efs-deploy"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.11"
  handler       = "deploy.lambda_handler"
  timeout       = 30

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  vpc_config {
    subnet_ids         = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_group_ids = [aws_security_group.ec2_sg.id]
  }

  file_system_config {
    arn              = aws_efs_access_point.lambda_ap.arn
    local_mount_path = "/mnt/efs"
  }
}

