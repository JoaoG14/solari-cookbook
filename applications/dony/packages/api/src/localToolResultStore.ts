import type { DonyDatabase } from './database';

import {
  nativeAgentLocalToolResultSchema,
  type NativeAgentLocalToolResult
} from '@dony/domain';

import { config } from './config';
import { createDatabase } from './database';

const pollIntervalMs = 250;
const defaultTtlMs = 2 * 60 * 1000;

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

const parseLocalToolResult = (value: unknown): NativeAgentLocalToolResult => {
  const result = nativeAgentLocalToolResultSchema.parse(value);

  return {
    ...result,
    metadata: result.metadata ?? null
  };
};

export class LocalToolResultStore {
  private readonly pool: DonyDatabase;

  public constructor(pool = createDatabase(config.d1)) {
    this.pool = pool;
  }

  public async migrate(): Promise<void> {
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS native_agent_local_tool_results (
        run_id TEXT NOT NULL,
        call_id TEXT NOT NULL,
        result TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
        consumed_at TEXT,
        PRIMARY KEY (run_id, call_id)
      );
    `);
    await this.pool.query(`
      CREATE INDEX IF NOT EXISTS native_agent_local_tool_results_created_idx
      ON native_agent_local_tool_results(created_at);
    `);
    await this.pool.trackTables(['native_agent_local_tool_results']);
  }

  public async save(
    runId: string,
    result: NativeAgentLocalToolResult
  ): Promise<void> {
    await this.pool.query(
      `
      INSERT INTO native_agent_local_tool_results (
        run_id,
        call_id,
        result,
        created_at,
        consumed_at
      )
      VALUES ($1, $2, $3, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), NULL)
      ON CONFLICT (run_id, call_id) DO UPDATE SET
        result = EXCLUDED.result,
        created_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
        consumed_at = NULL;
      `,
      [runId, result.callId, JSON.stringify(result)]
    );
  }

  public async waitFor(
    runId: string,
    callId: string,
    signal: AbortSignal,
    ttlMs = defaultTtlMs
  ): Promise<NativeAgentLocalToolResult> {
    const expiresAt = Date.now() + ttlMs;

    while (Date.now() < expiresAt) {
      if (signal.aborted) {
        throw new Error('Local tool request was canceled.');
      }

      const result = await this.consume(runId, callId);

      if (result) {
        return result;
      }

      await sleep(pollIntervalMs);
    }

    throw new Error('Timed out waiting for local tool result.');
  }

  public async cleanupExpired(ttlMs = defaultTtlMs): Promise<void> {
    await this.pool.query(
      `
      DELETE FROM native_agent_local_tool_results
      WHERE created_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', $1);
      `,
      [`-${Math.ceil(ttlMs / 1000)} seconds`]
    );
  }

  private async consume(
    runId: string,
    callId: string
  ): Promise<NativeAgentLocalToolResult | null> {
    const result = await this.pool.query(
      `
      UPDATE native_agent_local_tool_results
      SET consumed_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
      WHERE run_id = $1
        AND call_id = $2
        AND consumed_at IS NULL
      RETURNING result;
      `,
      [runId, callId]
    );
    const row = result.rows[0] as { result: unknown } | undefined;

    return row ? parseLocalToolResult(row.result) : null;
  }
}

export const localToolResultStore = new LocalToolResultStore();
