import { Miniflare } from 'miniflare';
import { DonyDatabase } from '../../src/database';
import { remoteD1 } from '../../src/d1/client';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// Run the production queries and atomic batches in Cloudflare's D1 runtime.
export const companionTestDatabase = async (directory?: string) => {
  const runtime = new Miniflare({
    modules: true,
    scriptPath: resolve(dirname(fileURLToPath(import.meta.url)), '../../d1/worker.js'),
    bindings: { DONY_D1_TOKEN: 'dony-test-database-token' },
    compatibilityDate: '2026-07-30',
    d1Databases: { DB: 'dony-test' },
    ...(directory ? { d1Persist: directory } : {})
  });
  const request: typeof fetch = (input, init) =>
    runtime.dispatchFetch(
      String(input),
      init as never
    ) as unknown as Promise<Response>;
  const pool = new DonyDatabase(
    remoteD1(
      { url: 'http://dony-d1.test', token: 'dony-test-database-token' },
      request
    )
  );
  await pool.initialize();
  return { database: { close: () => runtime.dispose() }, pool, request };
};
