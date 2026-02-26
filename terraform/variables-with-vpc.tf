# Variables for VPC deployment
# Use with main-with-vpc.tf

variable "group_name" {
  description = "Name of the bot group (used for resource naming)"
  type        = string
}

variable "agent_names" {
  description = "Names for each bot agent"
  type        = list(string)
  default     = ["agent1", "agent2", "agent3"]
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "ami_id" {
  description = "AMI ID (Ubuntu 22.04 LTS)"
  type        = string
  default     = "ami-0c55b159cbfafe1f0"  # Ubuntu 22.04 in us-east-2
}

variable "bot_instance_type" {
  description = "Instance type for bot instances"
  type        = string
  default     = "t3.medium"
}

variable "redis_instance_type" {
  description = "Instance type for Redis instance"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "neon_dsn" {
  description = "Neon Postgres connection string"
  type        = string
  sensitive   = true
}

variable "redis_password" {
  description = "Redis password (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "clawdbot_version" {
  description = "Clawdbot version to install"
  type        = string
  default     = "latest"
}
