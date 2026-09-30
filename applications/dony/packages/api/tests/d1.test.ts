import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { betterAuth } from 'better-auth';
import { bearer } from 'better-auth/plugins';
import { getMigrations } from 'better-auth/db/migration';
import { companionTestDatabase } from './helpers/companionDatabase';
import { CloudStore } from '../src/cloudStore';
import { DonyDatabase } from '../src/database';
import { CompanionStore } from '../src/companionStore';
import { randomUUID } from 'node:crypto';

let db: Awaited<ReturnType<typeof companionTestDatabase>>;
beforeEach(async () => {
  db = await companionTestDatabase();
});
afterEach(async () => {
  await db.database.close();
});

describe('D1 atomic writes', () => {
  it('rolls back an entire batch when any statement fails', async () => {
    await db.pool.query(
      'CREATE TABLE example (id TEXT PRIMARY KEY, value INTEGER NOT NULL)'
    );
    await db.pool.trackTables(['example']);
    await expect(
      db.pool.transaction(async (client) => {
        await client.query("INSERT INTO example VALUES ('one', 1)");
        await client.query("INSERT INTO example VALUES ('one', 2)");
      })
    ).rejects.toThrow();
    expect((await db.pool.query('SELECT * FROM example')).rows).toEqual([]);
  });

  it('retries conflicting read-modify-write operations without losing updates', async () => {
    await db.pool.query(
      'CREATE TABLE example (id TEXT PRIMARY KEY, value INTEGER NOT NULL)'
    );
    await db.pool.trackTables(['example']);
    await db.pool.query("INSERT INTO example VALUES ('one', 0)");
    await Promise.all(
      Array.from({ length: 5 }, () =>
        db.pool.transaction(async (client) => {
          const { rows } = await client.query(
            "SELECT value FROM example WHERE id = 'one'"
          );
          await client.query("UPDATE example SET value = $1 WHERE id = 'one'", [
            rows[0]!.value + 1
          ]);
        })
      )
    );
    expect((await db.pool.query('SELECT value FROM example')).rows).toEqual([
      { value: 5 }
    ]);
  });

  it('reserves the budget atomically across independent API clients', async () => {
    const store = new CloudStore(db.pool);
    await store.migrate();
    const job = await store.createOnboardingJob('alice');
    const results = await Promise.allSettled(
      Array.from({ length: 5 }, () => new CloudStore(new DonyDatabase(db.pool.send)).reserve(job, 3))
    );
    expect(
      results.filter((result) => result.status === 'fulfilled')
    ).toHaveLength(3);
    expect((await store.status('alice', true)).dailySpentUsd).toBe(9);
  });

  it('claims each cloud job once across competing workers', async () => {
    const store = new CloudStore(db.pool);
    await store.migrate();
    await store.settings('alice', { pro: true });
    const workspace = await store.workspace(db.pool, 'alice');
    await db.pool.query(
      'INSERT INTO cloud_jobs(id, workspace_id, thread_id, assistant_message_id, kind) VALUES ($1,$2,$3,$4,$5)',
      [randomUUID(), workspace.id, randomUUID(), randomUUID(), 'chat']
    );
    const claims = await Promise.all([
      store.claim(),
      store.claim(),
      store.claim()
    ]);
    expect(claims.filter(Boolean)).toHaveLength(1);
  });

  it('consumes a pairing code once under concurrent requests', async () => {
    const store = new CompanionStore(db.pool);
    await store.migrate();
    const id = randomUUID();
    await store.register('alice', id, 'Mac');
    const { code } = await store.pairCode('alice', id);
    const results = await Promise.allSettled([
      store.pair(code, 'one'),
      store.pair(code, 'two')
    ]);
    expect(
      results.filter((result) => result.status === 'fulfilled')
    ).toHaveLength(1);
  });
});

it('migrates and uses Better Auth accounts and bearer sessions on D1', async () => {
  const auth = betterAuth({
    database: db.pool.binding as never,
    secret: 'dony-d1-test-secret-at-least-thirty-two-characters',
    baseURL: 'http://localhost:8787',
    emailAndPassword: { enabled: true },
    plugins: [bearer()]
  });
  await (await getMigrations(auth.options)).runMigrations();
  await (await getMigrations(auth.options)).runMigrations();
  const result = await auth.api.signUpEmail({
    body: {
      email: 'd1@example.com',
      password: 'safe-test-password',
      name: 'D1 test'
    }
  });
  expect(result.token).toBeTruthy();
  const session = await auth.api.getSession({
    headers: new Headers({ authorization: `Bearer ${result.token}` })
  });
  expect(session?.user.id).toBe(result.user.id);
  expect(session?.user.email).toBe('d1@example.com');
});

it('stores large JSON in chunks and deletes it with the owning row', async () => {
  const store = new CloudStore(db.pool);
  await store.migrate();
  const workspace = await store.workspace(db.pool, 'alice');
  const id = randomUUID();
  const file = {
    name: 'large.txt',
    mimeType: 'text/plain',
    base64: Buffer.alloc(3_000_000, 'x').toString('base64')
  };
  await db.pool.query(
    'INSERT INTO cloud_artifacts(id, workspace_id, thread_id, file) VALUES ($1,$2,$3,$4)',
    [id, workspace.id, randomUUID(), JSON.stringify(file)]
  );
  expect(
    (
      await db.pool.query('SELECT file FROM cloud_artifacts WHERE id = $1', [
        id
      ])
    ).rows[0]!.file
  ).toEqual(file);
  expect(
    (await db.pool.query('SELECT count(*) AS count FROM dony_json_chunks'))
      .rows[0]!.count
  ).toBeGreaterThan(1);
  await db.pool.query('DELETE FROM cloud_artifacts WHERE id = $1', [id]);
  expect(
    (await db.pool.query('SELECT count(*) AS count FROM dony_json_chunks'))
      .rows[0]!.count
  ).toBe(0);
});

it('does not interpret user-supplied JSON as an internal chunk reference', async () => {
  await db.pool.query(
    'CREATE TABLE example (id TEXT PRIMARY KEY, result TEXT)'
  );
  await db.pool.trackTables(['example']);
  const malicious = { __dony_json_chunks: 'someone-elses-data', parts: 1 };
  await db.pool.query('INSERT INTO example VALUES ($1,$2)', ['one', malicious]);
  expect(
    (await db.pool.query('SELECT result FROM example')).rows[0]!.result
  ).toEqual(malicious);
});

it('rejects unauthenticated access to the database gateway', async () => {
  const response = await db.request('http://dony-d1.test/query', {
    method: 'POST',
    body: JSON.stringify({ batch: [{ sql: 'SELECT * FROM dony_revision' }] })
  });
  expect(response.status).toBe(401);
});

it('does not retain chunks when a conditional update affects no row', async () => {
  await db.pool.query(
    'CREATE TABLE example (id TEXT PRIMARY KEY, result TEXT)'
  );
  await db.pool.trackTables(['example']);
  const value = JSON.stringify('x'.repeat(3_000_000));
  const result = await db.pool.query(
    'UPDATE example SET result = $1 WHERE id = $2 RETURNING result',
    [value, 'missing']
  );
  expect(result.rows).toEqual([]);
  expect(
    (await db.pool.query('SELECT count(*) AS count FROM dony_json_chunks'))
      .rows[0]!.count
  ).toBe(0);
});
