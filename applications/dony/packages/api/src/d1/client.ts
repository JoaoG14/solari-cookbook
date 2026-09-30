export type Statement = { sql: string; params?: unknown[] };
export type D1Result = {
  success: boolean;
  results: Record<string, unknown>[];
  meta: { changes?: number; last_row_id?: number };
};
export type D1Transport = (statements: Statement[]) => Promise<D1Result[]>;
export type D1Config = { url: string; token: string };

export class D1QuotaExceededError extends Error {
  constructor() { super('The Cloudflare database gateway request quota is exhausted.'); }
}

export function remoteD1(
  config: D1Config,
  request: typeof fetch = fetch
): D1Transport {
  return async (batch) => {
    if (!config.url || !config.token)
      throw new Error('DONY_D1_URL and DONY_D1_TOKEN are required.');
    const response = await request(new URL('/query', config.url), {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${config.token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ batch }),
      signal: AbortSignal.timeout(30_000)
    });
    // Cloudflare returns text/HTML rather than our Worker JSON after quota exhaustion.
    if (response.status === 429) throw new D1QuotaExceededError();
    const body = (await response.json()) as {
      success: boolean;
      result?: D1Result[];
      errors?: { message: string }[];
    };
    if (
      !response.ok ||
      !body.success ||
      body.result?.some((item) => !item.success)
    ) {
      // Never include SQL parameters, credentials, or user data in errors.
      const conflict = body.errors?.some((item) =>
        item.message.includes('dony_transaction_conflict')
      );
      throw new Error(
        conflict
          ? 'dony_transaction_conflict'
          : `D1 request failed (${response.status}).`
      );
    }
    if (!body.result) throw new Error('D1 returned no query results.');
    return body.result;
  };
}

// Better Auth uses D1's prepared-statement API. Keep raw SQLite values here;
// Better Auth owns its date/boolean conversion.
export class D1Binding {
  constructor(readonly send: D1Transport) {}
  prepare(sql: string) {
    return new D1Statement(this, { sql });
  }
  batch(statements: D1Statement[]) {
    return this.send(statements.map((item) => item.statement));
  }
  async exec(sql: string) {
    await this.send([{ sql }]);
    return { count: 1, duration: 0 };
  }
}
class D1Statement {
  constructor(
    private readonly binding: D1Binding,
    readonly statement: Statement
  ) {}
  bind(...params: unknown[]) {
    return new D1Statement(this.binding, { ...this.statement, params });
  }
  async all() {
    return (await this.binding.send([this.statement]))[0]!;
  }
  run() {
    return this.all();
  }
  async first(column?: string) {
    const row = (await this.all()).results[0];
    return column ? (row?.[column] ?? null) : (row ?? null);
  }
}
