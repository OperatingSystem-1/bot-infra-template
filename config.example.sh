#!/bin/bash
# Bot Group Configuration

# Group identity
GROUP_NAME="alpha"                    # Used for naming resources
GROUP_DESCRIPTION="First agent group"

# Agent configuration
AGENT_NAMES=("alice" "bob" "charlie") # Names for each agent
AGENT_COUNT=${#AGENT_NAMES[@]}        # Auto-calculated

# AWS configuration
AWS_REGION="us-east-2"
AWS_INSTANCE_TYPE="t3.medium"         # Per-agent instance type
AWS_REDIS_INSTANCE_TYPE="t3.small"    # Redis instance type
AWS_AMI="ami-0c55b159cbfafe1f0"        # Ubuntu 22.04 LTS
AWS_KEY_NAME="FIXME"                  # SSH key pair name - set to your actual key
AWS_SUBNET_ID="subnet-xxx"            # VPC subnet
AWS_VPC_ID="vpc-xxx"                  # VPC ID

# Neon Postgres (shared across groups or per-group)
# NEON_DSN="postgresql://YOUR_USER:YOUR_PASS@YOUR_HOST/YOUR_DB?sslmode=require"
NEON_DSN=""  # Set in your actual config.sh (not committed)
NEON_SHARED=true                      # true = use existing, false = create new

# Clawdbot configuration
CLAWDBOT_VERSION="latest"
ANTHROPIC_AUTH_MODE="oauth"           # oauth or api-key

# Redis configuration
REDIS_PORT=6379
# REDIS_PASSWORD - Set in your actual config.sh if you want auth

# SSH access
SSH_KEY_PATH="${HOME}/.ssh/your-key.pem"  # Update to your actual key path
SSH_USER="ubuntu"

# Networking
ALLOW_INTER_AGENT_PORTS="6379,8080,18789"  # Redis, API, Clawdbot gateway
