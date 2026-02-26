# Bot Group Infrastructure Template

Template for provisioning new groups of AI agents with full coordination infrastructure.

## What Gets Created

For each bot group:
1. **N EC2 instances** (one per agent)
2. **1 Redis instance** (pub/sub coordination)
3. **Security group** (allows inter-agent communication)
4. **Neon Postgres tables** (shared or per-group)
5. **Deployed agent-sync scripts** (tq, dispatcher, etc.)

## Prerequisites

- AWS CLI configured with appropriate IAM permissions
- SSH key for EC2 access
- Neon Postgres connection string
- TribeClaw account (for Clawdbot licensing)

## Quick Start

```bash
# 1. Configure your group
cp config.example.sh config.sh
vim config.sh  # Set GROUP_NAME, AGENT_COUNT, etc.

# 2. Provision infrastructure
./provision.sh

# 3. Deploy agent-sync to all instances
./deploy-group.sh

# 4. Register agents with Clawdbot
./register-agents.sh
```

## Directory Structure

```
infra-template/
├── README.md
├── config.example.sh      # Example configuration
├── provision.sh           # Creates EC2 + Redis + security groups
├── deploy-group.sh        # Deploys agent-sync to all instances
├── register-agents.sh     # Registers agents with Clawdbot
├── teardown.sh            # Destroys all resources
├── terraform/             # Terraform alternative (optional)
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── user-data/
    ├── agent-init.sh      # EC2 user data script
    └── redis-init.sh      # Redis instance init
```
