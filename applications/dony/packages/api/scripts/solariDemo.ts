import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import { companionTestDatabase } from '../tests/helpers/companionDatabase';
import { CloudBrowser } from '../src/cloudBrowser';
import { createCloudModel } from '../src/cloudModel';
import { CloudWorker } from '../src/cloudWorker';
import { createMobileRoutes } from '../src/mobileRoutes';
import { createMobileAuthRoutes, migrateMobileAuth } from '../src/mobileAuth';
import { DemoStore } from './demoStore';

for (const name of ['SOLARI_API_KEY', 'DONY_OPENROUTER_API_KEY']) {
  if (!process.env[name]) throw new Error(`Add ${name} to .env before starting the Solari demo.`);
}
// Supply local defaults before loading the inherited backend configuration.
const token = process.env.DONY_API_DEV_AUTH_TOKEN ?? 'dony-solari-local-dev';
process.env.DONY_API_DEV_AUTH_TOKEN = token;
process.env.DONY_COMPOSIO_ENABLED = 'false';
const { composioConnectorService } = await import('../src/composioConnectorService');
const database = await companionTestDatabase();
const store = new DemoStore(database.pool);
await store.migrate();
await migrateMobileAuth(database.pool);
const user = { id: 'dony-solari-demo', name: 'Solari demo', email: null, avatarUrl: null };
await store.settings(user.id, { pro: true });
const browser = new CloudBrowser(process.env.SOLARI_API_KEY);
const model = createCloudModel(store, {
  apiKey: process.env.DONY_OPENROUTER_API_KEY!,
  ...(process.env.DONY_CLOUD_MODEL ? { model: process.env.DONY_CLOUD_MODEL } : {})
});
const worker = new CloudWorker(store, model, composioConnectorService, browser);
const app = new Hono();
app.get('/health', (c) => c.json({ ok: true, mode: 'local-solari-demo' }));
// Only the development PKCE flow is used; external authentication stays disabled.
const authentication = { api: { getSession: async () => null } } as unknown as Parameters<typeof createMobileAuthRoutes>[1];
app.route('/v1/mobile/auth', createMobileAuthRoutes(database.pool, authentication, 'http://127.0.0.1:8787', { token, user }));
app.route('/v1/mobile', createMobileRoutes(store,
  async (headers) => headers.get('authorization') === `Bearer ${token}` ? user : Response.json({}, { status: 401 }),
  true, composioConnectorService, model, undefined, browser));
store.onWorkAvailable = () => worker.wake();
worker.start();
const server = serve({ fetch: app.fetch, hostname: '127.0.0.1', port: 8787 }, () => {
  console.log('Solari demo on http://127.0.0.1:8787. Run Dony Solari in the simulator and sign in with Continue with Google.');
  console.log('Disposable local data; real Solari/OpenRouter usage. Press Ctrl-C to stop.');
});
async function stop() {
  worker.stop();
  await browser.closeAll();
  server.close();
  await database.database.close();
  process.exit(0);
}
process.once('SIGINT', () => void stop());
process.once('SIGTERM', () => void stop());
