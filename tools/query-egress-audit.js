#!/usr/bin/env node
/**
 * Query Egress Audit Logs
 * View and analyze external API calls logged in tq_egress_audit
 * 
 * Usage:
 *   node query-egress-audit.js recent [bot_name] [limit]
 *   node query-egress-audit.js stats [bot_name] [time_window]
 *   node query-egress-audit.js top-destinations [limit]
 *   node query-egress-audit.js errors [bot_name]
 */

const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.NEON_DSN || 'postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require'
});

async function recentCalls(bot_name = null, limit = 50) {
  const query = bot_name
    ? `SELECT bot_name, destination_url, http_method, status_code, latency_ms, created_at
       FROM tq_egress_audit
       WHERE bot_name = $1
       ORDER BY created_at DESC
       LIMIT $2`
    : `SELECT bot_name, destination_url, http_method, status_code, latency_ms, created_at
       FROM tq_egress_audit
       ORDER BY created_at DESC
       LIMIT $1`;
  
  const params = bot_name ? [bot_name, limit] : [limit];
  const result = await pool.query(query, params);
  
  console.log(`\n📋 Recent egress calls${bot_name ? ` for ${bot_name}` : ''} (last ${limit}):\n`);
  console.table(result.rows);
}

async function stats(bot_name = null, timeWindow = '1 day') {
  const query = bot_name
    ? `SELECT
         bot_name,
         COUNT(*) as total_calls,
         COUNT(DISTINCT destination_url) as unique_urls,
         AVG(latency_ms)::INT as avg_latency_ms,
         MAX(latency_ms) as max_latency_ms,
         MIN(latency_ms) as min_latency_ms,
         SUM(request_size_bytes) as total_request_bytes,
         SUM(response_size_bytes) as total_response_bytes,
         COUNT(CASE WHEN status_code >= 400 THEN 1 END) as errors,
         COUNT(CASE WHEN status_code >= 500 THEN 1 END) as server_errors
       FROM tq_egress_audit
       WHERE bot_name = $1
         AND created_at > NOW() - INTERVAL '${timeWindow}'
       GROUP BY bot_name`
    : `SELECT
         bot_name,
         COUNT(*) as total_calls,
         COUNT(DISTINCT destination_url) as unique_urls,
         AVG(latency_ms)::INT as avg_latency_ms,
         SUM(request_size_bytes) as total_request_bytes,
         SUM(response_size_bytes) as total_response_bytes,
         COUNT(CASE WHEN status_code >= 400 THEN 1 END) as errors
       FROM tq_egress_audit
       WHERE created_at > NOW() - INTERVAL '${timeWindow}'
       GROUP BY bot_name
       ORDER BY total_calls DESC`;
  
  const params = bot_name ? [bot_name] : [];
  const result = await pool.query(query, params);
  
  console.log(`\n📊 Egress stats${bot_name ? ` for ${bot_name}` : ''} (last ${timeWindow}):\n`);
  console.table(result.rows);
}

async function topDestinations(limit = 20) {
  const result = await pool.query(`
    SELECT
      destination_url,
      COUNT(*) as call_count,
      COUNT(DISTINCT bot_name) as bot_count,
      AVG(latency_ms)::INT as avg_latency_ms,
      COUNT(CASE WHEN status_code >= 400 THEN 1 END) as error_count
    FROM tq_egress_audit
    WHERE created_at > NOW() - INTERVAL '1 day'
    GROUP BY destination_url
    ORDER BY call_count DESC
    LIMIT $1
  `, [limit]);
  
  console.log(`\n🎯 Top ${limit} destinations (last 24 hours):\n`);
  console.table(result.rows);
}

async function errors(bot_name = null) {
  const query = bot_name
    ? `SELECT bot_name, destination_url, http_method, status_code, latency_ms, created_at
       FROM tq_egress_audit
       WHERE bot_name = $1 AND status_code >= 400
       ORDER BY created_at DESC
       LIMIT 50`
    : `SELECT bot_name, destination_url, http_method, status_code, latency_ms, created_at
       FROM tq_egress_audit
       WHERE status_code >= 400
       ORDER BY created_at DESC
       LIMIT 50`;
  
  const params = bot_name ? [bot_name] : [];
  const result = await pool.query(query, params);
  
  console.log(`\n❌ Recent errors${bot_name ? ` for ${bot_name}` : ''} (status >= 400):\n`);
  if (result.rows.length === 0) {
    console.log('  No errors found!');
  } else {
    console.table(result.rows);
  }
}

async function timeSeriesActivity(bot_name = null, interval = '1 hour', duration = '24 hours') {
  const query = bot_name
    ? `SELECT
         date_trunc('${interval}', created_at) as time_bucket,
         COUNT(*) as calls,
         COUNT(DISTINCT destination_url) as unique_urls,
         AVG(latency_ms)::INT as avg_latency
       FROM tq_egress_audit
       WHERE bot_name = $1
         AND created_at > NOW() - INTERVAL '${duration}'
       GROUP BY time_bucket
       ORDER BY time_bucket DESC`
    : `SELECT
         date_trunc('${interval}', created_at) as time_bucket,
         COUNT(*) as calls,
         COUNT(DISTINCT bot_name) as active_bots,
         AVG(latency_ms)::INT as avg_latency
       FROM tq_egress_audit
       WHERE created_at > NOW() - INTERVAL '${duration}'
       GROUP BY time_bucket
       ORDER BY time_bucket DESC`;
  
  const params = bot_name ? [bot_name] : [];
  const result = await pool.query(query, params);
  
  console.log(`\n📈 Activity by ${interval}${bot_name ? ` for ${bot_name}` : ''} (last ${duration}):\n`);
  console.table(result.rows);
}

// CLI mode
if (require.main === module) {
  const [command, ...args] = process.argv.slice(2);
  
  const commands = {
    recent: () => recentCalls(args[0], args[1] ? parseInt(args[1]) : 50),
    stats: () => stats(args[0], args[1] || '1 day'),
    'top-destinations': () => topDestinations(args[0] ? parseInt(args[0]) : 20),
    errors: () => errors(args[0]),
    timeseries: () => timeSeriesActivity(args[0], args[1] || '1 hour', args[2] || '24 hours')
  };

  if (!command || !commands[command]) {
    console.log(`
Usage: node query-egress-audit.js <command> [options]

Commands:
  recent [bot_name] [limit]              - Show recent egress calls
  stats [bot_name] [time_window]         - Show egress statistics
  top-destinations [limit]               - Show most-called destinations
  errors [bot_name]                      - Show failed requests
  timeseries [bot_name] [interval] [dur] - Show activity over time

Examples:
  node query-egress-audit.js recent jean 100
  node query-egress-audit.js stats samantha "6 hours"
  node query-egress-audit.js top-destinations 10
  node query-egress-audit.js errors
  node query-egress-audit.js timeseries jean "15 minutes" "6 hours"
    `);
    process.exit(1);
  }

  commands[command]()
    .then(() => pool.end())
    .catch(error => {
      console.error('❌ Error:', error.message);
      pool.end();
      process.exit(1);
    });
}

module.exports = {
  recentCalls,
  stats,
  topDestinations,
  errors,
  timeSeriesActivity
};


