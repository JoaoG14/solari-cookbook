import { readFileSync } from 'node:fs';

import { PGlite } from '@electric-sql/pglite';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  new URL('../migrations/20260907_relax_account_issuer.sql', import.meta.url),
  'utf8'
);

describe('Better Auth 1.7.3 account migration', () => {
  it('preserves existing accounts and allows inserts without an issuer', async () => {
    const database = await PGlite.create();

    try {
      await database.exec(`
        CREATE TABLE account (
          id TEXT PRIMARY KEY,
          "providerId" TEXT NOT NULL,
          "accountId" TEXT NOT NULL,
          issuer TEXT NOT NULL
        );
        CREATE UNIQUE INDEX "account_issuer_accountId_uidx"
          ON account (issuer, "accountId");
        INSERT INTO account VALUES ('existing', 'google', '123', 'google');
      `);

      await expect(
        database.exec(`INSERT INTO account (id, "providerId", "accountId")
          VALUES ('new', 'google', '456')`)
      ).rejects.toThrow('null value in column "issuer"');

      await database.exec(migration);
      await database.exec(migration);
      await database.exec(`INSERT INTO account (id, "providerId", "accountId")
        VALUES ('new', 'google', '456')`);

      expect(
        (await database.query('SELECT * FROM account ORDER BY id')).rows
      ).toEqual([
        {
          id: 'existing',
          providerId: 'google',
          accountId: '123',
          issuer: 'google'
        },
        { id: 'new', providerId: 'google', accountId: '456', issuer: null }
      ]);
      expect(
        (
          await database.query(`SELECT indexname FROM pg_indexes
        WHERE indexname = 'account_issuer_accountId_uidx'`)
        ).rows
      ).toEqual([]);
    } finally {
      await database.close();
    }
  });

  it('leaves fresh databases and schemas without issuer unchanged', async () => {
    const database = await PGlite.create();

    try {
      await database.exec(migration);
      await database.exec('CREATE TABLE account (id TEXT PRIMARY KEY)');
      await database.exec(migration);
      await database.exec("INSERT INTO account VALUES ('existing')");
      expect((await database.query('SELECT * FROM account')).rows).toEqual([
        { id: 'existing' }
      ]);
    } finally {
      await database.close();
    }
  });
});
