terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "key_name" {
  description = "terraformkey"
  type        = string
}

# Get latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Security Group
resource "aws_security_group" "app_sg" {
  name        = "docker-app-sg"
  description = "Security group for Docker app with monitoring"

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Flask app
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Grafana
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance
resource "aws_instance" "app" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.small"
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e
              exec > >(tee /var/log/user-data.log)
              exec 2>&1

              echo "Starting Docker setup..."

              # Update system
              apt-get update
              apt-get upgrade -y

              # Install Docker
              apt-get install -y ca-certificates curl gnupg
              install -m 0755 -d /etc/apt/keyrings
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
              chmod a+r /etc/apt/keyrings/docker.gpg

              echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
                tee /etc/apt/sources.list.d/docker.list > /dev/null

              apt-get update
              apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

              # Start Docker
              systemctl enable docker
              systemctl start docker

              # Add ubuntu user to docker group
              usermod -aG docker ubuntu

              # Create app directory for deployment
              mkdir -p /opt/app
              chown -R ubuntu:ubuntu /opt/app

              echo "Docker setup complete! Ready for GitHub Actions deployment."
              EOF

  tags = {
    Name = "docker-app-instance"
  }
}

# Outputs
output "instance_ip" {
  value       = aws_instance.app.public_ip
  description = "Public IP of your EC2 instance"
}

output "ssh_command" {
  value = "ssh -i ${var.key_name}.pem ubuntu@${aws_instance.app.public_ip}"
}

output "next_steps" {
  value = <<-EOT
  
  ✅ EC2 instance with Docker created!
  
  Wait ~3 minutes for Docker installation to complete.
  
  Add these GitHub Secrets:
    - EC2_SSH_KEY: Your SSH private key
    - EC2_HOST: ${aws_instance.app.public_ip}
  
  Then push your code to deploy all containers:
    - Flask App (port 5000)
    - Prometheus (port 9090)
    - Grafana (port 3000)
    - Node Exporter (port 9100)
  
  Verify Docker is ready:
    ssh -i ${var.key_name}.pem ubuntu@${aws_instance.app.public_ip}
    docker --version
  EOT
}