import { encodeJson, decodeJson, jsonCleanupTriggers } from './d1/json';
import { setTimeout as delay } from 'node:timers/promises';
import {
  D1Binding,
  D1QuotaExceededError,
  remoteD1,
  type D1Config,
  type D1Transport,
  type Statement
} from './d1/client';

export type QueryResult<T = Record<string, any>> = {
  rows: T[];
  rowCount: number;
};
export interface QueryClient {
  query<T = Record<string, any>>(
    sql: string,
    parameters?: unknown[]
  ): Promise<QueryResult<T>>;
}
const jsonColumns = new Set([
  'snapshot',
  'receipt',
  'action',
  'messages',
  'files',
  'result',
  'file',
  'user_data',
  'last_exchange_reply'
]);
const dateColumns = new Set([
  'created_at',
  'expires_at',
  'consumed_at',
  'revoked_at',
  'last_seen_at',
  'lease_until',
  'checked_at',
  'sent_at'
]);

function statement(
  sql: string,
  parameters: unknown[] = []
): { statements: Statement[]; resultIndex: number } {
  const writes: Statement[] = [];
  const encoded = new Map<number, unknown>();
  const params: unknown[] = [];
  const compiled = sql.replace(/\$(\d+)/g, (_, index: string) => {
    const value = parameters[Number(index) - 1];
    if (value === undefined) throw new Error('Missing D1 query parameter.');
    if (!encoded.has(Number(index))) {
      let parameter =
        value instanceof Date
          ? value.toISOString()
          : typeof value === 'boolean'
            ? Number(value)
            : value !== null && typeof value === 'object'
              ? JSON.stringify(value)
              : value;
      if (typeof parameter === 'string' && /^\s*(INSERT|UPDATE)\b/i.test(sql))
        parameter = encodeJson(parameter, writes);
      encoded.set(Number(index), parameter);
    }
    params.push(encoded.get(Number(index)));
    return '?';
  });
  const resultIndex = writes.length;
  const chunkIds = [...new Set(writes.map((write) => write.params![0]))];
  writes.push({ sql: compiled, params });
  // A canceled job or ignored insert may update no row. Remove its unreferenced
  // chunks in this same batch; changes() refers to the owning statement.
  if (chunkIds.length)
    writes.push({
      sql: 'DELETE FROM dony_json_chunks WHERE id IN (SELECT value FROM json_each(?)) AND changes() = 0',
      params: [JSON.stringify(chunkIds)]
    });
  return { statements: writes, resultIndex };
}

// Callbacks may read and stage writes, but must not perform external actions or
// depend on reading their staged writes. A checked D1 batch commits everything.
export class D1Transaction implements QueryClient {
  readonly writes: Statement[] = [];
  constructor(private readonly database: DonyDatabase) {}
  async query<T = Record<string, any>>(
    sql: string,
    parameters?: unknown[]
  ): Promise<QueryResult<T>> {
    if (/^\s*SELECT\b/i.test(sql))
      return this.database.query<T>(sql, parameters);
    if (/\bRETURNING\b/i.test(sql))
      throw new Error('Read the row before staging a D1 transaction write.');
    this.writes.push(...statement(sql, parameters).statements);
    return { rows: [], rowCount: 0 };
  }
}

export class DonyDatabase implements QueryClient {
  readonly binding: D1Binding;
  constructor(readonly send: D1Transport) {
    this.binding = new D1Binding(send);
  }
  async query<T = Record<string, any>>(
    sql: string,
    parameters?: unknown[]
  ): Promise<QueryResult<T>> {
    for (let attempt = 0; ; attempt += 1) {
      try {
        return await this.queryOnce<T>(sql, parameters);
      } catch (error) {
        if (
          attempt >= 2 ||
          !/^\s*SELECT\b/i.test(sql) ||
          !(error instanceof Error) ||
          error.message !== 'Dony JSON changed during the read.'
        )
          throw error;
      }
    }
  }
  private async queryOnce<T>(
    sql: string,
    parameters?: unknown[]
  ): Promise<QueryResult<T>> {
    const prepared = statement(sql, parameters);
    const schema = /^\s*CREATE\b/i.test(sql);
    const statements = schema
      ? sql
          .split(';')
          .filter((part) => part.trim())
          .flatMap((part) => statement(part).statements)
      : prepared.statements;
    const results = await this.send(statements);
    const result = results[schema ? results.length - 1 : prepared.resultIndex]!;
    const rows = await Promise.all(
      result.results.map(async (row) => {
        const decoded: Record<string, unknown> = {};
        for (const [key, value] of Object.entries(row)) {
          decoded[key] = value;
          if (value !== null && typeof value === 'string') {
            if (jsonColumns.has(key))
              decoded[key] = await decodeJson(value, async (id) => {
                const chunks = await this.send([
                  {
                    sql: 'SELECT data FROM dony_json_chunks WHERE id = ? ORDER BY part',
                    params: [id]
                  }
                ]);
                return chunks[0]!.results as { data: string }[];
              });
            else if (dateColumns.has(key)) decoded[key] = new Date(value);
          }
          if (key === 'pro' || key === 'matches') decoded[key] = Boolean(value);
        }
        return decoded as T;
      })
    );
    return { rows, rowCount: rows.length || result.meta.changes || 0 };
  }
  async initialize() {
    await this.send([
      {
        sql: 'CREATE TABLE IF NOT EXISTS dony_json_chunks (id TEXT NOT NULL, part INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY(id, part))'
      },
      {
        sql: 'CREATE TABLE IF NOT EXISTS dony_revision (id INTEGER PRIMARY KEY CHECK(id = 1), revision INTEGER NOT NULL)'
      },
      { sql: 'INSERT OR IGNORE INTO dony_revision VALUES (1, 0)' },
      {
        sql: 'CREATE TABLE IF NOT EXISTS dony_transaction_guard (value INTEGER CONSTRAINT dony_transaction_conflict CHECK(value = 0))'
      }
    ]);
  }
  async trackTables(tables: string[]) {
    await this.initialize();
    for (const table of tables) {
      if (!/^[a-z_]+$/.test(table)) throw new Error('Invalid Dony table.');
      await this.send(
        ['INSERT', 'UPDATE', 'DELETE'].map((event) => ({
          sql: `CREATE TRIGGER IF NOT EXISTS revision_${table}_${event} AFTER ${event} ON ${table}
         BEGIN UPDATE dony_revision SET revision = revision + 1 WHERE id = 1; END;`
        }))
      );
      const columns = await this.query<{ name: string }>(
        `SELECT name FROM pragma_table_info('${table}')`
      );
      for (const column of columns.rows) {
        if (jsonColumns.has(column.name))
          await this.send(jsonCleanupTriggers(table, column.name));
      }
    }
  }

  private async revision() {
    const result = await this.query<{ revision: number }>(
      'SELECT revision FROM dony_revision WHERE id = 1'
    );
    return result.rows[0]!.revision;
  }
  async transaction<T>(run: (client: D1Transaction) => Promise<T>): Promise<T> {
    for (let attempt = 0; attempt < 8; attempt += 1) {
      const revision = await this.revision();
      const client = new D1Transaction(this);
      let result: T;
      try {
        result = await run(client);
      } catch (error) {
        if ((await this.revision()) !== revision) continue;
        throw error;
      }
      try {
        // CHECK failure aborts the entire batch before any staged write executes.
        await this.send([
          {
            sql: 'INSERT INTO dony_transaction_guard(value) SELECT 1 WHERE (SELECT revision FROM dony_revision WHERE id = 1) != ?',
            params: [revision]
          },
          ...client.writes
        ]);
        return result;
      } catch (error) {
        if (
          !(error instanceof Error) ||
          !error.message.includes('dony_transaction_conflict')
        )
          throw error;
      }
    }
    throw new Error('Dony database changed repeatedly. Please retry.');
  }
}
export const createDatabase = (config: D1Config) =>
  new DonyDatabase(remoteD1(config));

type InitializeDatabaseOptions = {
  allowUnavailable: boolean;
  migrateAuth: () => Promise<void>;
  migrateLocalToolResults: () => Promise<void>;
  cleanupLocalToolResults: () => Promise<void>;
  warn?: (message: string) => void;
  waitForQuotaReset?: () => Promise<void>;
};

export const initializeDatabase = async ({
  allowUnavailable,
  migrateAuth,
  migrateLocalToolResults,
  cleanupLocalToolResults,
  warn = console.warn,
  waitForQuotaReset = () => delay(5 * 60_000)
}: InitializeDatabaseOptions): Promise<void> => {
  for (;;) {
    try {
      await migrateAuth();
      await migrateLocalToolResults();
      await cleanupLocalToolResults();
      return;
    } catch (error) {
      let cause = error;
      for (let depth = 0; depth < 10 && cause instanceof Error && !(cause instanceof D1QuotaExceededError); depth++)
        cause = cause.cause;
      if (!allowUnavailable && cause instanceof D1QuotaExceededError) {
        warn('Cloudflare request quota exhausted. Database startup will retry in five minutes.');
        await waitForQuotaReset();
        continue;
      }
      if (!allowUnavailable) {
        throw error;
      }

      const code =
        typeof error === 'object' &&
        error !== null &&
        'code' in error &&
        typeof error.code === 'string'
          ? ` (${error.code})`
          : '';

      warn(
        `Dony API database is unavailable in development${code}. ` +
          'Starting without database-backed auth and local tool results.'
      );
      return;
    }
  }
};
