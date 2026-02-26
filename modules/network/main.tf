# Network Module - Creates VPC from scratch
# For bot group infrastructure

variable "group_name" {
  description = "Name of the bot group"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone" {
  description = "AWS availability zone"
  type        = string
  default     = "us-east-2a"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name  = "${var.group_name}-vpc"
    Group = var.group_name
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name  = "${var.group_name}-igw"
    Group = var.group_name
  }
}

# Public Subnet (for bots with public IPs)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name  = "${var.group_name}-public"
    Group = var.group_name
    Type  = "public"
  }
}

# Private Subnet (for Redis - internal only)
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone = var.availability_zone

  tags = {
    Name  = "${var.group_name}-private"
    Group = var.group_name
    Type  = "private"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name  = "${var.group_name}-nat-eip"
    Group = var.group_name
  }
}

# NAT Gateway (allows private subnet to reach internet)
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name  = "${var.group_name}-nat"
    Group = var.group_name
  }

  depends_on = [aws_internet_gateway.main]
}

# Route Table - Public
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name  = "${var.group_name}-public-rt"
    Group = var.group_name
  }
}

# Route Table - Private
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name  = "${var.group_name}-private-rt"
    Group = var.group_name
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Security Group - Bots
resource "aws_security_group" "bots" {
  name        = "${var.group_name}-bots-sg"
  description = "Security group for bot instances"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Clawdbot gateway
  ingress {
    from_port   = 18789
    to_port     = 18789
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inter-bot communication
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
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
    Name  = "${var.group_name}-bots-sg"
    Group = var.group_name
  }
}

# Security Group - Redis
resource "aws_security_group" "redis" {
  name        = "${var.group_name}-redis-sg"
  description = "Security group for Redis instance"
  vpc_id      = aws_vpc.main.id

  # Redis from bots only
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.bots.id]
  }

  # SSH from bots only (for debugging)
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bots.id]
  }

  # Outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "${var.group_name}-redis-sg"
    Group = var.group_name
  }
}

# Outputs
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "bots_security_group_id" {
  value = aws_security_group.bots.id
}

output "redis_security_group_id" {
  value = aws_security_group.redis.id
}
