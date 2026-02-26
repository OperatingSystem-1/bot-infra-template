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

# Security group for inter-agent communication
resource "aws_security_group" "agents" {
  name        = "${var.group_name}-agents-sg"
  description = "Security group for ${var.group_name} agent group"
  vpc_id      = var.vpc_id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Redis (inter-agent)
  ingress {
    from_port = 6379
    to_port   = 6379
    protocol  = "tcp"
    self      = true
  }

  # API endpoints (inter-agent)
  ingress {
    from_port = 8080
    to_port   = 8080
    protocol  = "tcp"
    self      = true
  }

  # Clawdbot gateway (inter-agent)
  ingress {
    from_port = 18789
    to_port   = 18789
    protocol  = "tcp"
    self      = true
  }

  # Outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "${var.group_name}-agents-sg"
    Group = var.group_name
  }
}

# Redis instance
resource "aws_instance" "redis" {
  ami                    = var.ami_id
  instance_type          = var.redis_instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.agents.id]

  user_data = templatefile("${path.module}/../user-data/redis-init.sh", {
    redis_password = var.redis_password
  })

  tags = {
    Name  = "${var.group_name}-redis"
    Group = var.group_name
    Role  = "redis"
  }
}

# Agent instances
resource "aws_instance" "agent" {
  count = length(var.agent_names)

  ami                    = var.ami_id
  instance_type          = var.agent_instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.agents.id]

  user_data = templatefile("${path.module}/../user-data/agent-init.sh", {
    agent_name   = var.agent_names[count.index]
    group_name   = var.group_name
    redis_host   = aws_instance.redis.private_ip
    neon_dsn     = var.neon_dsn
    clawdbot_version = var.clawdbot_version
  })

  tags = {
    Name      = "${var.group_name}-${var.agent_names[count.index]}"
    Group     = var.group_name
    Role      = "agent"
    AgentName = var.agent_names[count.index]
  }

  depends_on = [aws_instance.redis]
}

# Register agents in Neon database
resource "null_resource" "register_agents" {
  count = length(var.agent_names)

  provisioner "local-exec" {
    command = <<-EOF
      psql "${var.neon_dsn}" -c "
        INSERT INTO bots (name, group_name, ec2_instance_id, ec2_public_ip, ec2_private_ip, created_at)
        VALUES ('${var.agent_names[count.index]}', '${var.group_name}', 
                '${aws_instance.agent[count.index].id}',
                '${aws_instance.agent[count.index].public_ip}',
                '${aws_instance.agent[count.index].private_ip}',
                NOW())
        ON CONFLICT (name) DO UPDATE SET
          ec2_instance_id = EXCLUDED.ec2_instance_id,
          ec2_public_ip = EXCLUDED.ec2_public_ip,
          ec2_private_ip = EXCLUDED.ec2_private_ip;
      "
    EOF
  }

  depends_on = [aws_instance.agent]
}
