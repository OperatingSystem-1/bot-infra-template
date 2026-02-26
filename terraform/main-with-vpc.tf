# Main configuration - Creates full VPC from scratch
# Use this when you need "whole new vpc, redis, etc"

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

# Network module - creates VPC, subnets, security groups
module "network" {
  source = "../modules/network"

  group_name        = var.group_name
  vpc_cidr          = var.vpc_cidr
  availability_zone = "${var.aws_region}a"
}

# Redis instance in private subnet
resource "aws_instance" "redis" {
  ami                    = var.ami_id
  instance_type          = var.redis_instance_type
  key_name               = var.key_name
  subnet_id              = module.network.private_subnet_id
  vpc_security_group_ids = [module.network.redis_security_group_id]

  user_data = templatefile("${path.module}/../user-data/redis-init.sh", {
    redis_password = var.redis_password
  })

  tags = {
    Name  = "${var.group_name}-redis"
    Group = var.group_name
    Role  = "redis"
  }
}

# Bot instances in public subnet
resource "aws_instance" "bot" {
  count = length(var.agent_names)

  ami                    = var.ami_id
  instance_type          = var.bot_instance_type
  key_name               = var.key_name
  subnet_id              = module.network.public_subnet_id
  vpc_security_group_ids = [module.network.bots_security_group_id]

  user_data = templatefile("${path.module}/../user-data/agent-init.sh", {
    agent_name       = var.agent_names[count.index]
    group_name       = var.group_name
    redis_host       = aws_instance.redis.private_ip
    neon_dsn         = var.neon_dsn
    clawdbot_version = var.clawdbot_version
  })

  tags = {
    Name      = "${var.group_name}-${var.agent_names[count.index]}"
    Group     = var.group_name
    Role      = "bot"
    AgentName = var.agent_names[count.index]
  }

  depends_on = [aws_instance.redis]
}

# Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "redis_private_ip" {
  description = "Redis private IP (for bot connection)"
  value       = aws_instance.redis.private_ip
}

output "bot_public_ips" {
  description = "Bot public IPs (for SSH access)"
  value       = aws_instance.bot[*].public_ip
}

output "bot_private_ips" {
  description = "Bot private IPs"
  value       = aws_instance.bot[*].private_ip
}

output "deployment_summary" {
  description = "Full deployment summary"
  value = {
    group_name = var.group_name
    vpc_id     = module.network.vpc_id
    redis_ip   = aws_instance.redis.private_ip
    bots = [
      for i, bot in aws_instance.bot : {
        name       = var.agent_names[i]
        public_ip  = bot.public_ip
        private_ip = bot.private_ip
      }
    ]
  }
}
