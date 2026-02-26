# Egress Audit System

**Created by:** Samantha  
**Date:** 2026-02-26  
**Purpose:** Track and audit all external API calls from bot instances

## Overview

This system provides comprehensive logging and analysis of outbound API requests from bot instances. All egress traffic is logged to the `tq_egress_audit` Neon table with full metadata for security, debugging, and cost tracking.

## Components

### 1. Database Schema (`tq_egress_audit`)

**Table structure:**
```sql
CREATE TABLE tq_egress_audit (
  id UUID PRIMARY KEY,              -- Unique log entry ID
  bot_name VARCHAR(64) NOT NULL,    -- Which bot made the call
  group_name VARCHAR(64),           -- Bot group (optional)
  destination_url TEXT NOT NULL,    -- Target URL
  http_method VARCHAR(10),          -- GET, POST, etc.
  status_code INT,                  -- HTTP response code
  request_size_bytes INT,           -- Request payload size
  response_size_bytes INT,          -- Response payload size
  latency_ms INT,                   -- Request duration
  user_agent TEXT,                  -- User agent string
  created_at TIMESTAMPTZ            -- When logged
);

**Indexes for performance:**
- `idx_egress_bot` - Fast lookups by bot name
- `idx_egress_time` - Fast time-range queries
- `idx_egress_dest` - Fast lookups by destination

### 2. Logging Script (`log-egress-audit.js`)

**Programmatic usage:**
```javascript
const { logEgressCall } = require('./log-egress-audit.js');

await logEgressCall({
  bot_name: 'jean',
  destination_url: 'https://api.anthropic.com/v1/messages',
  http_method: 'POST',
  status_code: 200,
  latency_ms: 1250,
  request_size_bytes: 1024,
  response_size_bytes: 2048,
  user_agent: 'Clawdbot/1.0',
  group_name: 'production'
});

**CLI usage:**
```bash
node log-egress-audit.js <bot_name> <url> [method] [status] [latency_ms]

# Example
node log-egress-audit.js samantha https://api.github.com/repos POST 201 450

### 3. Query Script (`query-egress-audit.js`)

**View recent calls:**
```bash
# All bots, last 50 calls
node query-egress-audit.js recent

# Specific bot, last 100 calls
node query-egress-audit.js recent jean 100

**Get statistics:**
```bash
# All bots in last 24 hours
node query-egress-audit.js stats

# Specific bot in last 6 hours
node query-egress-audit.js stats samantha "6 hours"

**Top destinations:**
```bash
# Top 20 destinations
node query-egress-audit.js top-destinations 20

**View errors:**
```bash
# All errors (status >= 400)
node query-egress-audit.js errors

# Errors for specific bot
node query-egress-audit.js errors jared

**Time series activity:**
```bash
# Hourly activity for last 24 hours
node query-egress-audit.js timeseries

# 15-minute buckets for specific bot
node query-egress-audit.js timeseries jean "15 minutes" "6 hours"

## Integration with Egress Gateway

The egress gateway (built by Jared) should call `logEgressCall()` for every outbound request:

**Example Squid log parser:**
```bash
#!/bin/bash
# Parse Squid access logs and send to Neon

tail -F /var/log/squid/access.log | while read -r line; do
  # Extract: timestamp, bot_name, url, method, status, bytes, latency
  BOT_NAME=$(echo "$line" | awk '{print $3}')
  URL=$(echo "$line" | awk '{print $7}')
  STATUS=$(echo "$line" | awk '{print $4}')
  LATENCY=$(echo "$line" | awk '{print $2}')
  
  node /opt/log-egress-audit.js "$BOT_NAME" "$URL" "GET" "$STATUS" "$LATENCY"
done

**Or use the module in gateway code:**
```javascript
// In egress gateway proxy
const { logEgressCall } = require('./log-egress-audit.js');

proxyServer.on('proxyReq', (proxyReq, req, res) => {
  const startTime = Date.now();
  
  res.on('finish', async () => {
    const latency = Date.now() - startTime;
    
    await logEgressCall({
      bot_name: req.headers['x-bot-name'] || 'unknown',
      destination_url: req.url,
      http_method: req.method,
      status_code: res.statusCode,
      latency_ms: latency,
      request_size_bytes: req.socket.bytesRead,
      response_size_bytes: req.socket.bytesWritten
    });
  });
});

## Use Cases

### 1. Security Auditing
```bash
# Check what APIs a bot is calling
node query-egress-audit.js recent jean

# Look for suspicious destinations
node query-egress-audit.js top-destinations

### 2. Cost Tracking
```bash
# See API usage per bot
node query-egress-audit.js stats

# Analyze which destinations are most expensive
SELECT destination_url, COUNT(*) as calls, SUM(response_size_bytes) as total_bytes
FROM tq_egress_audit
WHERE created_at > NOW() - INTERVAL '1 day'
GROUP BY destination_url
ORDER BY total_bytes DESC;

### 3. Performance Monitoring
```bash
# Find slow API calls
SELECT bot_name, destination_url, latency_ms, created_at
FROM tq_egress_audit
WHERE latency_ms > 5000
ORDER BY created_at DESC;

### 4. Error Analysis
```bash
# Recent failures
node query-egress-audit.js errors

# Error rate by destination
SELECT destination_url,
  COUNT(*) as total_calls,
  COUNT(CASE WHEN status_code >= 400 THEN 1 END) as errors,
  (COUNT(CASE WHEN status_code >= 400 THEN 1 END)::FLOAT / COUNT(*) * 100)::INT as error_rate_pct
FROM tq_egress_audit
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY destination_url
HAVING COUNT(*) > 10
ORDER BY error_rate_pct DESC;

### 5. Compliance & Audit Trail
```bash
# Full audit trail for specific time period
SELECT *
FROM tq_egress_audit
WHERE created_at BETWEEN '2026-02-26 00:00:00' AND '2026-02-26 23:59:59'
ORDER BY created_at;

## Integration Checklist for Jared

- [ ] Squid proxy configured to log with bot metadata
- [ ] Log parser script calls `logEgressCall()` for each request
- [ ] Bot instances send `X-Bot-Name` header (or authenticated via IP)
- [ ] Systemd service for log parser (auto-restart)
- [ ] CloudWatch logs backup for Squid logs
- [ ] Alerting on high error rates (status >= 500)
- [ ] Dashboard for real-time egress monitoring

## Example Queries

**Most active bot:**
```sql
SELECT bot_name, COUNT(*) as calls
FROM tq_egress_audit
WHERE created_at > NOW() - INTERVAL '1 hour'
GROUP BY bot_name
ORDER BY calls DESC
LIMIT 1;

**Bandwidth usage by bot:**
```sql
SELECT
  bot_name,
  SUM(request_size_bytes + response_size_bytes) as total_bytes,
  (SUM(request_size_bytes + response_size_bytes) / 1024 / 1024)::INT as total_mb
FROM tq_egress_audit
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY bot_name
ORDER BY total_bytes DESC;

**API call patterns:**
```sql
SELECT
  date_trunc('hour', created_at) as hour,
  bot_name,
  COUNT(*) as calls
FROM tq_egress_audit
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY hour, bot_name
ORDER BY hour DESC, calls DESC;

## Files Delivered

1. **Schema creation:** `tq_egress_audit` table in Neon ✅
2. **Logger:** `/home/ubuntu/clawd/auth-layer/log-egress-audit.js` (4KB)
3. **Query tool:** `/home/ubuntu/clawd/auth-layer/query-egress-audit.js` (7KB)
4. **Documentation:** This README

**Total:** ~12KB of code + schema + docs

## Testing

```bash
# Test logging
node log-egress-audit.js test-bot https://api.example.com GET 200 150

# Verify log
node query-egress-audit.js recent test-bot 1

# Check stats
node query-egress-audit.js stats test-bot

## Next Steps

1. **Jared:** Integrate with egress gateway Squid proxy
2. **Boss:** Configure alerting thresholds (error rate, latency spikes)
3. **Jean:** Build CloudWatch dashboard for real-time monitoring
4. **All:** Start logging production traffic and validate data

---

**Owner:** Samantha  
**Status:** ✅ Complete and tested  
**Integration:** Ready for Jared's egress gateway module


**Location to add in repo:**
- auth-layer/log-egress-audit.js
- auth-layer/query-egress-audit.js
- auth-layer/EGRESS-AUDIT-README.md

**Or put in:**
- tools/egress-audit/log.js
- tools/egress-audit/query.js  
- tools/egress-audit/README.md

**Attribution:** Created by Samantha, 2026-02-26

Thanks for pushing these!
