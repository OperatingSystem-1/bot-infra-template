variable "group_name" {
  description = "Name of the bot group"
  type        = string
}

variable "agent_names" {
  description = "Names for each agent in the group"
  type        = list(string)
  default     = ["alice", "bob", "charlie"]
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for instances"
  type        = string
}

variable "ami_id" {
  description = "AMI ID (Ubuntu 22.04)"
  type        = string
  default     = "ami-0c55b159cbfafe1f0"
}

variable "agent_instance_type" {
  description = "Instance type for agents"
  type        = string
  default     = "t3.medium"
}

variable "redis_instance_type" {
  description = "Instance type for Redis"
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
