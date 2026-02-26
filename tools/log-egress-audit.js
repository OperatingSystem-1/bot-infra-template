#!/usr/bin/env node
/**
 * Egress Audit Logger
 * Logs external API calls to tq_egress_audit table
 * 
 * Usage:
 *   node log-egress-audit.js <bot_name> <url> <method> <status> <latency_ms>
 * 
 * Or import and use programmatically:
 *   const { logEgressCall } = require('./log-egress-audit.js');
 *   await logEgressCall('jean', 'https://api.example.com', 'GET', 200, 150);
 */

const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.NEON_DSN || 'postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require'
});

/**
 * Log an egress API call to Neon
 * @param {Object} callData - The egress call data
 * @param {string} callData.bot_name - Name of the bot making the call
 * @param {string} callData.destination_url - Target URL
 * @param {string} [callData.http_method] - HTTP method (GET, POST, etc.)
 * @param {number} [callData.status_code] - HTTP response status code
 * @param {number} [callData.latency_ms] - Request latency in milliseconds
 * @param {number} [callData.request_size_bytes] - Request payload size
 * @param {number} [callData.response_size_bytes] - Response payload size
 * @param {string} [callData.user_agent] - User agent string
 * @param {string} [callData.group_name] - Bot group name
 */
async function logEgressCall(callData) {
  const {
    bot_name,
    destination_url,
    http_method = null,
    status_code = null,
    latency_ms = null,
    request_size_bytes = null,
    response_size_bytes = null,
    user_agent = null,
    group_name = null
  } = callData;

  if (!bot_name || !destination_url) {
    throw new Error('bot_name and destination_url are required');
  }

  try {
    await pool.query(`
      INSERT INTO tq_egress_audit (
        bot_name, group_name, destination_url, http_method,
        status_code, request_size_bytes, response_size_bytes,
        latency_ms, user_agent
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    `, [
      bot_name,
      group_name,
      destination_url,
      http_method,
      status_code,
      request_size_bytes,
      response_size_bytes,
      latency_ms,
      user_agent
    ]);
  } catch (error) {
    console.error('Failed to log egress call:', error.message);
    throw error;
  }
}

/**
 * Get recent egress calls for a bot
 * @param {string} bot_name - Bot to query
 * @param {number} [limit=100] - Max results
 */
async function getRecentCalls(bot_name, limit = 100) {
  const result = await pool.query(`
    SELECT *
    FROM tq_egress_audit
    WHERE bot_name = $1
    ORDER BY created_at DESC
    LIMIT $2
  `, [bot_name, limit]);
  
  return result.rows;
}

/**
 * Get egress stats for a bot
 * @param {string} bot_name - Bot to query
 * @param {string} [since='1 day'] - Time window (e.g., '1 hour', '1 day')
 */
async function getEgressStats(bot_name, since = '1 day') {
  const result = await pool.query(`
    SELECT
      COUNT(*) as total_calls,
      COUNT(DISTINCT destination_url) as unique_destinations,
      AVG(latency_ms) as avg_latency_ms,
      SUM(request_size_bytes) as total_request_bytes,
      SUM(response_size_bytes) as total_response_bytes,
      COUNT(CASE WHEN status_code >= 400 THEN 1 END) as error_count
    FROM tq_egress_audit
    WHERE bot_name = $1
      AND created_at > NOW() - INTERVAL '${since}'
  `, [bot_name]);
  
  return result.rows[0];
}

// CLI mode
if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.length < 2) {
    console.error('Usage: node log-egress-audit.js <bot_name> <url> [method] [status] [latency_ms]');
    process.exit(1);
  }

  const [bot_name, destination_url, http_method, status_code, latency_ms] = args;

  logEgressCall({
    bot_name,
    destination_url,
    http_method,
    status_code: status_code ? parseInt(status_code) : null,
    latency_ms: latency_ms ? parseInt(latency_ms) : null
  })
    .then(() => {
      console.log('✅ Logged egress call');
      pool.end();
    })
    .catch(error => {
      console.error('❌ Error:', error.message);
      pool.end();
      process.exit(1);
    });
}

module.exports = {
  logEgressCall,
  getRecentCalls,
  getEgressStats
};


