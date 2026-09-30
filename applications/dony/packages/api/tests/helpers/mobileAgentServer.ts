// Disposable mobile UI fixture using the production cloud routes and in-memory Postgres.
// Run: pnpm --filter @dony/api exec tsx tests/helpers/mobileAgentServer.ts
import { randomUUID } from 'node:crypto';
import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import { companionTestDatabase } from './companionDatabase';
import { CloudStore } from '../../src/cloudStore';
import { createMobileRoutes } from '../../src/mobileRoutes';
import type { composioConnectorService } from '../../src/composioConnectorService';

const database = await companionTestDatabase();
const store = new CloudStore(database.pool);
await store.migrate();
let userId = randomUUID();
const app = new Hono();
app.post('/reset', async (c) => {
  userId = randomUUID();
  await store.settings(userId, { pro: true });
  return c.json({
    workspaceId: (await store.workspace(store.pool, userId)).id
  });
});
app.get('/snapshot', async (c) =>
  c.json((await store.state(userId, -1, [])).snapshot)
);
app.route(
  '/v1/mobile',
  createMobileRoutes(
    store,
    async (headers) =>
      headers.get('authorization') === 'Bearer agent-ui-test'
        ? { id: userId, name: null, email: null, avatarUrl: null }
        : Response.json({}, { status: 401 }),
    true,
    {} as typeof composioConnectorService
  )
);
serve({ fetch: app.fetch, hostname: '127.0.0.1', port: 18790 }, () => {
  console.log('Agent UI fixture ready on 127.0.0.1:18790');
});
