# Deploy Bot Group with New VPC

This guide creates a complete bot group infrastructure from scratch, including:
- New VPC with public/private subnets
- Internet Gateway and NAT Gateway
- Redis instance (private subnet)
- Bot instances (public subnet)
- Security groups for isolation

## Prerequisites

1. AWS CLI configured with appropriate IAM permissions
2. Terraform installed
3. SSH key pair in AWS
4. Neon Postgres connection string

## Quick Start

```bash
cd terraform

# Copy the VPC-enabled config
cp main-with-vpc.tf main.tf
cp variables-with-vpc.tf variables.tf

# Initialize Terraform
terraform init

# Create terraform.tfvars
cat > terraform.tfvars << 'EOF'
group_name    = "alpha"
agent_names   = ["alice", "bob", "charlie"]
aws_region    = "us-east-2"
key_name      = "your-ssh-key"
neon_dsn      = "postgresql://user:pass@host/db?sslmode=require"
EOF

# Preview the deployment
terraform plan

# Deploy
terraform apply
```

## What Gets Created

### Network Layer
- VPC (10.0.0.0/16 by default)
- Public subnet (10.0.1.0/24) - for bots
- Private subnet (10.0.2.0/24) - for Redis
- Internet Gateway
- NAT Gateway (allows private subnet internet access)
- Route tables

### Security Groups
- `{group_name}-bots-sg`: SSH (22), Clawdbot (18789), inter-bot traffic
- `{group_name}-redis-sg`: Redis (6379) from bots only

### Instances
- Redis: Private subnet, accessible only from bots
- Bots: Public subnet with public IPs for SSH access

## Outputs

After deployment:
```bash
terraform output vpc_id
terraform output redis_private_ip
terraform output bot_public_ips
```

## SSH Access

```bash
# Get bot IPs
terraform output bot_public_ips

# SSH to a bot
ssh -i ~/.ssh/your-key.pem ubuntu@<bot-public-ip>
```

## Cost Estimate

| Resource | Type | Monthly Cost |
|----------|------|-------------|
| NAT Gateway | - | ~$32 |
| Redis | t3.small | ~$15 |
| Bot (each) | t3.medium | ~$30 |
| **Total (3 bots)** | - | **~$137/month** |

## Teardown

```bash
terraform destroy
```

This removes all resources including VPC, instances, and networking.
