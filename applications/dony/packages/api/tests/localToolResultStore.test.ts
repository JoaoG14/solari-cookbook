import { afterEach, describe, expect, it, vi } from 'vitest';

type QueryCall = {
  sql: string;
  params: unknown[];
};

const createPool = (responses: unknown[] = []) => {
  const calls: QueryCall[] = [];
  const query = vi.fn((sql: string, params: unknown[] = []) => {
    calls.push({ sql, params });
    const response = responses.shift();

    return Promise.resolve(response ?? { rows: [] });
  });

  return {
    pool: { query },
    calls
  };
};

const importStore = async () => {
  vi.stubEnv('DATABASE_URL', 'postgres://dony:dony@127.0.0.1:5432/dony');
  vi.stubEnv('DONY_API_DEV_AUTH_TOKEN', 'dev-token');
  vi.resetModules();

  return import('../src/localToolResultStore');
};

afterEach(() => {
  vi.unstubAllEnvs();
});

describe('LocalToolResultStore', () => {
  it('saves local tool results keyed by run and call', async () => {
    const { LocalToolResultStore } = await importStore();
    const { pool, calls } = createPool();
    const store = new LocalToolResultStore(pool as never);

    await store.save('run-1', {
      callId: 'call-1',
      status: 'success',
      content: 'done'
    });

    expect(calls[0]?.params).toEqual([
      'run-1',
      'call-1',
      JSON.stringify({
        callId: 'call-1',
        status: 'success',
        content: 'done'
      })
    ]);
  });

  it('waits until a result is available and consumes it', async () => {
    const { LocalToolResultStore } = await importStore();
    const { pool } = createPool([
      { rows: [] },
      {
        rows: [
          {
            result: {
              callId: 'call-1',
              status: 'success',
              content: 'done'
            }
          }
        ]
      }
    ]);
    const store = new LocalToolResultStore(pool as never);

    await expect(
      store.waitFor('run-1', 'call-1', new AbortController().signal, 1_000)
    ).resolves.toEqual({
      callId: 'call-1',
      status: 'success',
      content: 'done',
      metadata: null
    });
  });

  it('times out when no result is written', async () => {
    const { LocalToolResultStore } = await importStore();
    const { pool } = createPool([{ rows: [] }, { rows: [] }]);
    const store = new LocalToolResultStore(pool as never);

    await expect(
      store.waitFor('run-1', 'call-1', new AbortController().signal, 1)
    ).rejects.toThrow('Timed out waiting for local tool result.');
  });

  it('preserves screenshot images through saving and consuming a result', async () => {
    const { LocalToolResultStore } = await importStore();
    const responses: unknown[] = [];
    const { pool, calls } = createPool(responses);
    const store = new LocalToolResultStore(pool as never);
    const result = {
      callId: 'capture-1',
      status: 'success' as const,
      content: '{"snapshot_id":"s12345678"}',
      images: [{ data: 'a'.repeat(100_000), mimeType: 'image/png' as const }]
    };
    await store.save('run-1', result);
    responses.push({
      rows: [{ result: JSON.parse(calls[0]!.params[2] as string) as unknown }]
    });
    await expect(
      store.waitFor('run-1', 'capture-1', new AbortController().signal)
    ).resolves.toEqual({ ...result, metadata: null });
  });
});
