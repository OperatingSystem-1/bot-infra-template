#!/bin/bash
# Redis instance initialization
set -e

# Install Redis
apt-get update
apt-get install -y redis-server

# Configure Redis for network access
cat > /etc/redis/redis.conf << 'EOF'
bind 0.0.0.0
protected-mode no
port 6379
daemonize yes
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log
databases 16
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
dbfilename dump.rdb
dir /var/lib/redis
maxmemory 256mb
maxmemory-policy allkeys-lru
appendonly yes
appendfsync everysec
EOF

%{ if redis_password != "" }
echo "requirepass ${redis_password}" >> /etc/redis/redis.conf
%{ endif }

# Restart Redis with new config
systemctl restart redis-server
systemctl enable redis-server

# Verify Redis is running
sleep 2
redis-cli ping

echo "Redis initialized successfully"
