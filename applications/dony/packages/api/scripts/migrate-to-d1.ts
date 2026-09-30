import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { Pool } from 'pg';
import { betterAuth } from 'better-auth';
import { bearer } from 'better-auth/plugins';
import { getMigrations } from 'better-auth/db/migration';
import { createDatabase } from '../src/database';
import { CloudStore } from '../src/cloudStore';
import { CompanionStore } from '../src/companionStore';
import { migrateMobileAuth } from '../src/mobileAuth';
import { LocalToolResultStore } from '../src/localToolResultStore';

// Parent tables precede dependants. Keep even expired sessions and command receipts.
const tables = [
  'user',
  'account',
  'session',
  'verification',
  'cloud_workspaces',
  'cloud_receipts',
  'cloud_desktops',
  'cloud_jobs',
  'cloud_spend',
  'cloud_budget_days',
  'cloud_tool_calls',
  'cloud_push_devices',
  'cloud_notifications',
  'cloud_artifacts',
  'companion_desktops',
  'companion_pairings',
  'companion_devices',
  'companion_commands',
  'mobile_auth_handoffs',
  'native_agent_local_tool_results'
];
type Export = {
  version: 1;
  exportedAt: string;
  tables: Record<
    string,
    {
      columns: { name: string; type: string }[];
      rows: Record<string, unknown>[];
    }
  >;
};
const quote = (name: string) => `"${name.replaceAll('"', '""')}"`;
const normalize = (value: unknown, type: string): unknown => {
  if (value === null) return null;
  if (type.includes('timestamp'))
    return new Date(value as string).toISOString();
  if (['bigint', 'integer', 'smallint'].includes(type)) {
    const number = Number(value);
    if (!Number.isSafeInteger(number))
      throw new Error('Source integer exceeds JavaScript safe range.');
    return number;
  }
  if (type === 'boolean') return Boolean(value);
  if (type === 'date')
    return value instanceof Date
      ? value.toISOString().slice(0, 10)
      : String(value).slice(0, 10);
  return value;
};

async function main() {
  const [operation, path, stopped] = process.argv.slice(2);
  if (!['--export', '--import', '--verify'].includes(operation ?? '') || !path)
    throw new Error(
      'Usage: migrate-to-d1.ts --export|--import|--verify /private/backup.json [--source-writes-stopped]'
    );
  if (operation === '--export') {
    const connectionString =
      process.env.SOURCE_DATABASE_URL ?? process.env.DATABASE_URL;
    if (!connectionString) throw new Error('SOURCE_DATABASE_URL is required.');
    const source = new Pool({
      connectionString,
      connectionTimeoutMillis: 10_000
    });
    const client = await source.connect();
    try {
      await client.query(
        'BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY'
      );
      const sourceTables = await client.query<{ table_name: string }>(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'"
      );
      if (sourceTables.rows.some((row) => !tables.includes(row.table_name)))
        throw new Error('Source contains unmapped tables. Extend the migration before exporting.');
      const backup: Export = {
        version: 1,
        exportedAt: new Date().toISOString(),
        tables: {}
      };
      for (const table of tables) {
        const columns = await client.query<{ name: string; type: string }>(
          'SELECT column_name AS name, data_type AS type FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2 ORDER BY ordinal_position',
          ['public', table]
        );
        if (!columns.rows.length) continue;
        const { rows } = await client.query(`SELECT * FROM ${quote(table)}`);
        backup.tables[table] = {
          columns: columns.rows,
          rows: rows.map((row) =>
            Object.fromEntries(
              columns.rows.map(({ name, type }) => [
                name,
                normalize(row[name], type)
              ])
            )
          )
        };
        console.log(`${table}: ${rows.length} rows`);
      }
      await writeFile(resolve(path), JSON.stringify(backup), {
        mode: 0o600,
        flag: 'wx'
      });
      await client.query('COMMIT');
      console.log(
        'Read-only export complete. Backup contains private account and session data.'
      );
    } finally {
      await client.query('ROLLBACK');
      client.release();
      await source.end();
    }
    return;
  }
  const backup = JSON.parse(await readFile(resolve(path), 'utf8')) as Export;
  if (
    backup.version !== 1 ||
    Object.keys(backup.tables).some((name) => !tables.includes(name))
  )
    throw new Error('Unsupported Dony backup.');
  const target = createDatabase({
    url: process.env.DONY_D1_URL ?? '',
    token: process.env.DONY_D1_TOKEN ?? ''
  });
  if (operation === '--import') {
    if (stopped !== '--source-writes-stopped')
      throw new Error(
        'Stop source API/worker writes, take a final export, then pass --source-writes-stopped.'
      );
    // Refuse an existing app schema, including a partially imported database.
    const existing = await target.query(
      "SELECT name FROM sqlite_master WHERE type = 'table'"
    );
    if (existing.rows.some((row) => tables.includes(row.name)))
      throw new Error(
        'Target contains Dony tables. Import requires an empty D1 database.'
      );
    await target.initialize();
    const authentication = betterAuth({
      baseURL: 'http://localhost:8787',
      database: target.binding as never,
      plugins: [bearer()],
      logger: { disabled: true }
    });
    await (await getMigrations(authentication.options)).runMigrations();
    await new CloudStore(target).migrate();
    await new CompanionStore(target).migrate();
    await migrateMobileAuth(target);
    await new LocalToolResultStore(target).migrate();
    // Retain historical budget-day records even though D1 no longer uses their locks.
    await target.query(
      'CREATE TABLE IF NOT EXISTS cloud_budget_days (day TEXT PRIMARY KEY)'
    );
    for (const table of tables) {
      const data = backup.tables[table];
      if (!data) continue;
      const targetColumns = await target.query<{ name: string }>(
        `SELECT name FROM pragma_table_info('${table}')`
      );
      for (const column of data.columns) {
        if (targetColumns.rows.some((item) => item.name === column.name))
          continue;
        if (table !== 'account' || column.name !== 'issuer')
          throw new Error(`Unmapped source column: ${table}.${column.name}`);
        await target.query('ALTER TABLE account ADD COLUMN issuer TEXT');
      }
      const columns = data.columns
        .map((column) => quote(column.name))
        .join(',');
      const placeholders = data.columns
        .map((_, index) => `$${index + 1}`)
        .join(',');
      for (const row of data.rows)
        await target.query(
          `INSERT INTO ${quote(table)} (${columns}) VALUES (${placeholders})`,
          data.columns.map(({ name, type }) =>
            ['json', 'jsonb'].includes(type) && row[name] !== null
              ? JSON.stringify(row[name])
              : row[name]
          )
        );
      console.log(`${table}: imported ${data.rows.length} rows`);
    }
  }
  for (const table of tables) {
    const data = backup.tables[table];
    if (!data) continue;
    const actual = await target.query(`SELECT * FROM ${quote(table)}`);
    const canonical = (row: Record<string, unknown>) =>
      JSON.stringify(
        data.columns.map(({ name, type }) => normalize(row[name], type))
      );
    const expectedRows = data.rows.map(canonical).sort();
    const actualRows = actual.rows.map(canonical).sort();
    if (!isDeepStrictEqual(actualRows, expectedRows))
      throw new Error(
        `Verification failed for ${table}. Do not switch the API.`
      );
    console.log(`${table}: all ${actualRows.length} rows verified`);
  }
  const foreignKeys = await target.query('PRAGMA foreign_key_check');
  if (foreignKeys.rows.length)
    throw new Error('Target foreign-key verification failed.');
  console.log(
    'Every exported row verified. Keep the source and backup until live login, sync and agent checks pass.'
  );
}
main().catch((error) => {
  // Driver errors may contain source credentials or user data; do not print them.
  console.error(
    error instanceof Error && !('code' in error)
      ? error.message
      : 'Database migration failed. Source data was not changed.'
  );
  process.exitCode = 1;
});
