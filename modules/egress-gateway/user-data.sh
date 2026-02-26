#!/bin/bash
# Egress Gateway Setup - Squid proxy with audit logging
set -e

GROUP_NAME="${group_name}"
NEON_DSN="${neon_dsn}"

echo "=== Installing Squid proxy ==="
apt-get update
apt-get install -y squid postgresql-client python3-pip jq

echo "=== Configuring Squid ==="
cat > /etc/squid/squid.conf << 'SQUIDCONF'
# Squid proxy for bot egress gateway
http_port 3128

# Allow all outbound (bots are pre-authenticated by security group)
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl SSL_ports port 443
acl Safe_ports port 80 443 1025-65535

http_access allow localnet
http_access deny all

# Logging format with bot metadata
logformat audit %ts.%03tu %%{X-Bot-Name}>h %%{X-Group-Name}>h %>a %Ss/%03>Hs %<st %rm %ru %mt %<st

# Log to file for processing
access_log /var/log/squid/access.log audit
cache_log /var/log/squid/cache.log

# Performance tuning
cache deny all
forwarded_for on
SQUIDCONF

echo "=== Creating log shipper ==="
cat > /opt/log-shipper.py << 'PYTHONSCRIPT'
#!/usr/bin/env python3
"""Ship Squid access logs to Neon Postgres."""
import os
import time
import subprocess
import re
from datetime import datetime

NEON_DSN = os.environ.get('NEON_DSN', '')
LOG_FILE = '/var/log/squid/access.log'
POSITION_FILE = '/var/log/squid/.position'

def get_position():
    try:
        with open(POSITION_FILE, 'r') as f:
            return int(f.read().strip())
    except:
        return 0

def save_position(pos):
    with open(POSITION_FILE, 'w') as f:
        f.write(str(pos))

def parse_log_line(line):
    # Format: timestamp bot_name group_name client_ip status/code size method url content_type response_size
    parts = line.strip().split()
    if len(parts) < 8:
        return None
    
    try:
        timestamp = float(parts[0])
        bot_name = parts[1] if parts[1] != '-' else 'unknown'
        group_name = parts[2] if parts[2] != '-' else 'unknown'
        client_ip = parts[3]
        status_code = int(parts[4].split('/')[1]) if '/' in parts[4] else 0
        request_size = int(parts[5]) if parts[5].isdigit() else 0
        method = parts[6]
        url = parts[7]
        response_size = int(parts[8]) if len(parts) > 8 and parts[8].isdigit() else 0
        
        return {
            'timestamp': datetime.fromtimestamp(timestamp).isoformat(),
            'bot_name': bot_name,
            'group_name': group_name,
            'destination_url': url[:2000],  # Truncate long URLs
            'http_method': method[:10],
            'status_code': status_code,
            'request_size_bytes': request_size,
            'response_size_bytes': response_size,
            'latency_ms': 0,  # Not captured in this format
            'user_agent': ''
        }
    except Exception as e:
        print(f"Parse error: {e}")
        return None

def insert_record(record):
    sql = f"""
    INSERT INTO tq_egress_audit 
    (bot_name, group_name, destination_url, http_method, status_code, 
     request_size_bytes, response_size_bytes, latency_ms, user_agent)
    VALUES 
    ('{record['bot_name']}', '{record['group_name']}', '{record['destination_url']}',
     '{record['http_method']}', {record['status_code']}, {record['request_size_bytes']},
     {record['response_size_bytes']}, {record['latency_ms']}, '{record['user_agent']}');
    """
    try:
        subprocess.run(['psql', NEON_DSN, '-c', sql], 
                      capture_output=True, timeout=10)
    except Exception as e:
        print(f"Insert error: {e}")

def main():
    print("Log shipper started")
    while True:
        try:
            pos = get_position()
            with open(LOG_FILE, 'r') as f:
                f.seek(pos)
                lines = f.readlines()
                new_pos = f.tell()
            
            for line in lines:
                record = parse_log_line(line)
                if record:
                    insert_record(record)
            
            save_position(new_pos)
        except Exception as e:
            print(f"Error: {e}")
        
        time.sleep(5)

if __name__ == '__main__':
    main()
PYTHONSCRIPT

chmod +x /opt/log-shipper.py

echo "=== Creating systemd service for log shipper ==="
cat > /etc/systemd/system/log-shipper.service << 'SERVICECONF'
[Unit]
Description=Squid Log Shipper to Neon
After=squid.service

[Service]
Type=simple
Environment="NEON_DSN=$${NEON_DSN}"
ExecStart=/usr/bin/python3 /opt/log-shipper.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICECONF

# Replace placeholder with actual DSN
sed -i "s|\$${NEON_DSN}|$${NEON_DSN}|g" /etc/systemd/system/log-shipper.service

echo "=== Starting services ==="
systemctl restart squid
systemctl daemon-reload
systemctl enable log-shipper
systemctl start log-shipper

echo "=== Egress gateway setup complete ==="
echo "Proxy URL: http://$(hostname -I | awk '{print $1}'):3128"
