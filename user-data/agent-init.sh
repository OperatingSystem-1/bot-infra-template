#!/bin/bash
# Agent instance initialization
set -e

AGENT_NAME="${agent_name}"
GROUP_NAME="${group_name}"
REDIS_HOST="${redis_host}"
NEON_DSN="${neon_dsn}"
CLAWDBOT_VERSION="${clawdbot_version}"
HTTP_PROXY="${http_proxy}"
HTTPS_PROXY="${https_proxy}"

echo "Initializing agent: $AGENT_NAME (group: $GROUP_NAME)"

# Configure proxy if provided (egress gateway)
if [ -n "$HTTP_PROXY" ]; then
  echo "Configuring egress gateway proxy: $HTTP_PROXY"
  export http_proxy="$HTTP_PROXY"
  export https_proxy="$HTTPS_PROXY"
  export HTTP_PROXY="$HTTP_PROXY"
  export HTTPS_PROXY="$HTTPS_PROXY"
  export no_proxy="localhost,127.0.0.1,169.254.169.254,$REDIS_HOST"
  
  # Persist for all users
  cat >> /etc/environment << PROXYCONF
http_proxy=$HTTP_PROXY
https_proxy=$HTTPS_PROXY
HTTP_PROXY=$HTTP_PROXY
HTTPS_PROXY=$HTTPS_PROXY
no_proxy=localhost,127.0.0.1,169.254.169.254,$REDIS_HOST
PROXYCONF
fi

# Install system dependencies
apt-get update
apt-get install -y \
  nodejs npm \
  redis-tools \
  postgresql-client \
  jq \
  git \
  curl \
  chromium-browser

# Install Clawdbot
npm install -g clawdbot@$CLAWDBOT_VERSION

# Create workspace
mkdir -p /home/ubuntu/clawd
mkdir -p /home/ubuntu/.clawdbot/secrets
chown -R ubuntu:ubuntu /home/ubuntu/clawd /home/ubuntu/.clawdbot

# Set environment variables
cat > /home/ubuntu/.clawdbot/.env << EOF
AGENT_NAME=$AGENT_NAME
GROUP_NAME=$GROUP_NAME
REDIS_HOST=$REDIS_HOST
NEON_DATABASE_URL=$NEON_DSN
EOF
chown ubuntu:ubuntu /home/ubuntu/.clawdbot/.env
chmod 600 /home/ubuntu/.clawdbot/.env

# Wait for Redis to be available
echo "Waiting for Redis at $REDIS_HOST..."
for i in {1..30}; do
  if redis-cli -h "$REDIS_HOST" ping 2>/dev/null | grep -q PONG; then
    echo "Redis is ready"
    break
  fi
  sleep 2
done

# Test Neon connection
echo "Testing Neon connection..."
psql "$NEON_DSN" -c "SELECT 1" >/dev/null 2>&1 && echo "Neon is ready"

# Clone agent-sync if available
if gh repo view OperatingSystem-1/agent-sync >/dev/null 2>&1; then
  cd /home/ubuntu/clawd
  git clone https://github.com/OperatingSystem-1/agent-sync.git agent-sync 2>/dev/null || true
  chown -R ubuntu:ubuntu agent-sync
fi

echo "Agent $AGENT_NAME initialized successfully"
echo "Redis: $REDIS_HOST"
echo "Workspace: /home/ubuntu/clawd"
