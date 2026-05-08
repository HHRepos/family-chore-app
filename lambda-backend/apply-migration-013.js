const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');

const pool = new Pool({
  host: 'family-chore-db.cxegq20iy20d.eu-west-1.rds.amazonaws.com',
  port: 5432,
  database: 'familychoredb',
  user: 'choreadmin',
  password: 'ChoreApp2024Secure',
  ssl: { rejectUnauthorized: false }
});

async function run() {
  const client = await pool.connect();
  try {
    console.log('Connected to RDS Postgres');

    const migrationPath = path.join(
      __dirname,
      '..',
      'database',
      'migrations',
      '013_jobs_proposed_status.sql'
    );
    const sql = fs.readFileSync(migrationPath, 'utf8');

    console.log('Applying migration 013...');
    await client.query('BEGIN');
    await client.query(sql);
    await client.query('COMMIT');

    const result = await client.query(`
      SELECT con.conname, pg_get_constraintdef(con.oid) AS def
        FROM pg_constraint con
        JOIN pg_class cls ON cls.oid = con.conrelid
       WHERE cls.relname = 'jobs' AND con.contype = 'c'
       ORDER BY con.conname
    `);
    console.log('Current jobs CHECK constraints:');
    for (const row of result.rows) {
      console.log(`  ${row.conname}: ${row.def}`);
    }

    console.log('OK');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Migration failed:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

run();
