const { Pool } = require('pg');
require('dotenv').config();

// PostgreSQL connection config
// Prefers DATABASE_URL if available (as in Supabase, Neon, Render)
const isProduction = process.env.NODE_ENV === 'production';

const hasExternalDb = process.env.DATABASE_URL && 
                       !process.env.DATABASE_URL.includes('localhost') && 
                       !process.env.DATABASE_URL.includes('127.0.0.1');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/sig_microbuses',
  ssl: hasExternalDb ? { rejectUnauthorized: false } : false
});

pool.on('connect', () => {
  console.log('PostgreSQL database pool connected successfully');
});

pool.on('error', (err) => {
  console.error('Unexpected error on idle database client', err);
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  pool
};
