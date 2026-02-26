#!/bin/bash
# Provision EC2 instances and Redis for a new bot group
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "=== Provisioning Bot Group: $GROUP_NAME ==="
echo "Agents: ${AGENT_NAMES[*]}"
echo "Region: $AWS_REGION"

# Create security group for inter-agent communication
echo "[1/4] Creating security group..."
SG_NAME="${GROUP_NAME}-agents-sg"
SG_ID=$(aws ec2 create-security-group \
  --group-name "$SG_NAME" \
  --description "Security group for $GROUP_NAME agent group" \
  --vpc-id "$AWS_VPC_ID" \
  --region "$AWS_REGION" \
  --query 'GroupId' --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" \
    --region "$AWS_REGION" \
    --query 'SecurityGroups[0].GroupId' --output text)

echo "   Security Group: $SG_ID"

# Allow SSH from anywhere (tighten in production)
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 22 --cidr 0.0.0.0/0 \
  --region "$AWS_REGION" 2>/dev/null || true

# Allow inter-agent communication within the group
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 6379 --source-group "$SG_ID" \
  --region "$AWS_REGION" 2>/dev/null || true

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 8080 --source-group "$SG_ID" \
  --region "$AWS_REGION" 2>/dev/null || true

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 18789 --source-group "$SG_ID" \
  --region "$AWS_REGION" 2>/dev/null || true

# Create Redis instance
echo "[2/4] Launching Redis instance..."
REDIS_USER_DATA=$(cat << 'USERDATA'
#!/bin/bash
apt-get update
apt-get install -y redis-server
sed -i 's/bind 127.0.0.1/bind 0.0.0.0/' /etc/redis/redis.conf
sed -i 's/protected-mode yes/protected-mode no/' /etc/redis/redis.conf
systemctl restart redis
USERDATA
)

REDIS_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AWS_AMI" \
  --instance-type "$AWS_REDIS_INSTANCE_TYPE" \
  --key-name "$AWS_KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$AWS_SUBNET_ID" \
  --user-data "$REDIS_USER_DATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${GROUP_NAME}-redis},{Key=Group,Value=$GROUP_NAME},{Key=Role,Value=redis}]" \
  --region "$AWS_REGION" \
  --query 'Instances[0].InstanceId' --output text)

echo "   Redis Instance: $REDIS_INSTANCE_ID"

# Wait for Redis to get an IP
echo "   Waiting for Redis IP..."
REDIS_IP=""
for i in {1..30}; do
  REDIS_IP=$(aws ec2 describe-instances \
    --instance-ids "$REDIS_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
  if [ -n "$REDIS_IP" ] && [ "$REDIS_IP" != "None" ]; then
    break
  fi
  sleep 2
done
echo "   Redis IP: $REDIS_IP"

# Create agent instances
echo "[3/4] Launching agent instances..."
AGENT_IPS=()
AGENT_INSTANCE_IDS=()

for agent_name in "${AGENT_NAMES[@]}"; do
  AGENT_USER_DATA=$(cat << USERDATA
#!/bin/bash
# Agent initialization script
export AGENT_NAME="$agent_name"
export GROUP_NAME="$GROUP_NAME"
export REDIS_HOST="$REDIS_IP"

# Install dependencies
apt-get update
apt-get install -y nodejs npm redis-tools postgresql-client jq

# Install Clawdbot
npm install -g clawdbot@${CLAWDBOT_VERSION}

# Create workspace
mkdir -p /home/ubuntu/clawd
chown ubuntu:ubuntu /home/ubuntu/clawd

# Set environment
cat >> /home/ubuntu/.clawdbot/.env << EOF
AGENT_NAME=$agent_name
GROUP_NAME=$GROUP_NAME
REDIS_HOST=$REDIS_IP
NEON_DATABASE_URL=$NEON_DSN
EOF

echo "Agent $agent_name initialized"
USERDATA
)

  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AWS_AMI" \
    --instance-type "$AWS_INSTANCE_TYPE" \
    --key-name "$AWS_KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --subnet-id "$AWS_SUBNET_ID" \
    --user-data "$AGENT_USER_DATA" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${GROUP_NAME}-${agent_name}},{Key=Group,Value=$GROUP_NAME},{Key=Role,Value=agent},{Key=AgentName,Value=$agent_name}]" \
    --region "$AWS_REGION" \
    --query 'Instances[0].InstanceId' --output text)
  
  AGENT_INSTANCE_IDS+=("$INSTANCE_ID")
  echo "   $agent_name: $INSTANCE_ID"
done

# Wait for all instances and collect IPs
echo "[4/4] Waiting for instances to be ready..."
sleep 30

for i in "${!AGENT_NAMES[@]}"; do
  agent_name="${AGENT_NAMES[$i]}"
  instance_id="${AGENT_INSTANCE_IDS[$i]}"
  
  IP=$(aws ec2 describe-instances \
    --instance-ids "$instance_id" \
    --region "$AWS_REGION" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
  
  AGENT_IPS+=("$IP")
  echo "   $agent_name: $IP"
done

# Save group manifest
MANIFEST_FILE="$SCRIPT_DIR/groups/${GROUP_NAME}.json"
mkdir -p "$SCRIPT_DIR/groups"

cat > "$MANIFEST_FILE" << EOF
{
  "group_name": "$GROUP_NAME",
  "created_at": "$(date -Iseconds)",
  "region": "$AWS_REGION",
  "security_group_id": "$SG_ID",
  "redis": {
    "instance_id": "$REDIS_INSTANCE_ID",
    "private_ip": "$REDIS_IP"
  },
  "agents": [
$(for i in "${!AGENT_NAMES[@]}"; do
  comma=""
  [ $i -lt $((${#AGENT_NAMES[@]}-1)) ] && comma=","
  echo "    {\"name\": \"${AGENT_NAMES[$i]}\", \"instance_id\": \"${AGENT_INSTANCE_IDS[$i]}\", \"public_ip\": \"${AGENT_IPS[$i]}\"}$comma"
done)
  ]
}
EOF

echo ""
echo "=== Provisioning Complete ==="
echo "Manifest saved to: $MANIFEST_FILE"
echo ""
echo "Next steps:"
echo "  1. Wait 2-3 minutes for instances to finish initializing"
echo "  2. Run: ./deploy-group.sh $GROUP_NAME"
echo "  3. Run: ./register-agents.sh $GROUP_NAME"
