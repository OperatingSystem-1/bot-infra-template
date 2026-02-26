# Egress Gateway Module - Squid proxy for API audit
# All bot outbound traffic routes through this for logging

variable "group_name" {
  description = "Name of the bot group"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the egress gateway"
  type        = string
}

variable "ami_id" {
  description = "AMI ID (Ubuntu 22.04)"
  type        = string
}

variable "instance_type" {
  description = "Instance type for egress gateway"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "bots_security_group_id" {
  description = "Security group ID of bot instances"
  type        = string
}

variable "neon_dsn" {
  description = "Neon Postgres connection string for audit logging"
  type        = string
  sensitive   = true
}

# Security Group for Egress Gateway
resource "aws_security_group" "egress_gateway" {
  name        = "${var.group_name}-egress-sg"
  description = "Security group for egress gateway"
  vpc_id      = var.vpc_id

  # Squid proxy from bots
  ingress {
    from_port       = 3128
    to_port         = 3128
    protocol        = "tcp"
    security_groups = [var.bots_security_group_id]
  }

  # SSH from bots (debugging)
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bots_security_group_id]
  }

  # Outbound to internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "${var.group_name}-egress-sg"
    Group = var.group_name
    Role  = "egress-gateway"
  }
}

# Egress Gateway EC2 Instance
resource "aws_instance" "egress_gateway" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.egress_gateway.id]

  user_data = templatefile("${path.module}/user-data.sh", {
    group_name = var.group_name
    neon_dsn   = var.neon_dsn
  })

  tags = {
    Name  = "${var.group_name}-egress-gateway"
    Group = var.group_name
    Role  = "egress-gateway"
  }
}

# Outputs
output "egress_gateway_id" {
  value = aws_instance.egress_gateway.id
}

output "egress_gateway_private_ip" {
  value = aws_instance.egress_gateway.private_ip
}

output "egress_gateway_public_ip" {
  value = aws_instance.egress_gateway.public_ip
}

output "proxy_url" {
  value = "http://${aws_instance.egress_gateway.private_ip}:3128"
}

output "security_group_id" {
  value = aws_security_group.egress_gateway.id
}
