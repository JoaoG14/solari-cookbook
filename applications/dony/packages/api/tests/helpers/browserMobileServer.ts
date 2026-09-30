// Live Chrome frames + production worker/routes, with a scripted model.
// Local by default; DONY_BROWSER_FIXTURE_LIVE=1 opts into real Solari usage.
import { randomUUID } from 'node:crypto';
import { chromium } from 'patchright-core';
import { Solari, type BrowserSession } from '@solarisdk/browser';
import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import { companionTestDatabase } from './companionDatabase';
import { DemoStore } from '../../scripts/demoStore';
import { CloudBrowser } from '../../src/cloudBrowser';
import { CloudWorker } from '../../src/cloudWorker';
import type { CloudModel } from '../../src/cloudModel';
import { createMobileRoutes } from '../../src/mobileRoutes';
import type { composioConnectorService } from '../../src/composioConnectorService';

const database = await companionTestDatabase();
const store = new DemoStore(database.pool);
await store.migrate();
let closed = true;
let streams = 0;
let frames = 0;
const liveSolari = process.env.DONY_BROWSER_FIXTURE_LIVE === '1';
const fixtureHTML = `<!doctype html><html><head><title>Preview first page</title><style>body{font:32px system-ui;padding:60px;background:#f2eee8;color:#222}button{font:24px system-ui;padding:20px;border-radius:14px;background:#232b22;color:white}h1{font-size:60px}.pulse{width:48px;height:48px;background:#008859;border-radius:50%;animation:move 2s linear infinite alternate}@keyframes move{to{transform:translateX(900px)}}</style></head><body><h1>Dony browser preview</h1><p>The agent is browsing. You can watch here.</p><button onclick="document.title='Preview second page';document.querySelector('h1').textContent='The next page is ready';document.body.style.background='#dfe8db'">Next page</button><p id="clock"></p><div class="pulse"></div><script>setInterval(()=>document.getElementById('clock').textContent=new Date().toISOString(),100)</script></body></html>`;
const browser = new CloudBrowser('fixture', () => {
  const solari = liveSolari ? new Solari({ apiKey: process.env.SOLARI_API_KEY!, timeoutMs: 30_000, maxAttempts: 1 }) : undefined;
  return {
    launch: async () => {
      const local = solari ? await solari.launch() : await chromium.launch({ executablePath: process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
      closed = false;
      return {
        newContext: async (options: Parameters<typeof local.newContext>[0]) => {
          const context = await local.newContext(options);
          await context.route('http://127.0.0.1:18790/page', route => route.fulfill({ contentType: 'text/html', body: fixtureHTML }));
          const newCDPSession = context.newCDPSession.bind(context);
          context.newCDPSession = async page => {
            const cdp = await newCDPSession(page);
            streams++;
            cdp.on('close', () => { streams--; });
            cdp.on('Page.screencastFrame', () => { frames++; });
            return cdp;
          };
          return context;
        },
        close: async () => { await local.close(); closed = true; }
      } as BrowserSession;
    },
    close: async () => { await solari?.close(); }
  };
});
let advance: (() => void) | undefined;
let finish: (() => void) | undefined;
function waitForAction(set: (resolve: () => void) => void, signal: AbortSignal) {
  return new Promise<void>((resolve, reject) => {
    const aborted = () => reject(signal.reason);
    signal.addEventListener('abort', aborted, { once: true });
    set(() => { signal.removeEventListener('abort', aborted); resolve(); });
  });
}
let chatOnly = false;
let replyCount = 0;
const model: CloudModel = { configured: true, step: async (job, input) => {
  if (chatOnly) {
    replyCount++;
    const paragraphs = Array.from({ length: 8 }, (_, index) =>
      `Section ${index + 1}: Solar cells convert sunlight into electricity. Panels connect multiple cells, while a complete system includes an inverter and other equipment. [Source](https://en.wikipedia.org/wiki/Solar_cell).`);
    return { messages: [], text: `Research reply ${replyCount}\n\n${paragraphs.join('\n\n')}`, finished: true };
  }
  if (job.step === 0) {
    await input.tools.browser_use!.execute!({ action: 'open', url: 'http://127.0.0.1:18790/page' }, { toolCallId: 'open', messages: [] });
    return { messages: [], text: '', finished: false };
  }
  await waitForAction(resolve => { advance = resolve; }, input.signal);
  await input.tools.browser_use!.execute!({ action: 'click', role: 'button', name: 'Next page' }, { toolCallId: 'click', messages: [] });
  await waitForAction(resolve => { finish = resolve; }, input.signal);
  return { messages: [], text: 'I visited both pages.', finished: true };
} };
const connectors = { execute: async () => ({}) } as unknown as typeof composioConnectorService;
const worker = new CloudWorker(store, model, connectors, browser);
store.onWorkAvailable = () => worker.wake();
let userId = '';
let requests = 0;
let offline = false;
const app = new Hono();
app.get('/page', c => c.html(fixtureHTML));
app.post('/reset', async c => {
  worker.stop();
  await browser.closeAll();
  advance = undefined; finish = undefined;
  chatOnly = c.req.query('chat') === 'true'; replyCount = 0;
  userId = randomUUID(); requests = 0; frames = 0; offline = false;
  await store.settings(userId, { pro: true });
  const workspace = await store.workspace(store.pool, userId);
  const threadId = randomUUID();
  await store.command(userId, { id: randomUUID(), executionTarget: 'cloud', action: { type: 'chat.create', threadId, agentId: workspace.snapshot.agents[0]!.id } });
  if (!chatOnly) await store.command(userId, { id: randomUUID(), executionTarget: 'cloud', action: { type: 'chat.send', threadId, message: 'Show me the browser preview', files: [] } });
  worker.start(); worker.wake();
  return c.json({ workspaceId: workspace.id, threadId });
});
app.post('/advance', c => { advance?.(); return c.json({ ok: Boolean(advance) }); });
app.post('/finish', c => { finish?.(); return c.json({ ok: Boolean(finish) }); });
app.post('/offline', c => { offline = true; return c.json({ ok: true }); });
app.post('/online', c => { offline = false; return c.json({ ok: true }); });
app.get('/stats', c => c.json({ requests, closed, streams, frames, liveSolari }));
app.use('/v1/mobile/threads/:id/browser*', async (c, next) => {
  requests++;
  if (offline) return c.json({ error: 'Fixture offline' }, 503);
  await next();
});
app.route('/v1/mobile', createMobileRoutes(store,
  async headers => offline && headers.get('accept') === 'text/event-stream' ? Response.json({}, { status: 503 }) : headers.get('authorization') === 'Bearer agent-ui-test'
    ? { id: userId, name: null, email: null, avatarUrl: null } : Response.json({}, { status: 401 }),
  true, connectors, undefined, undefined, browser));
const server = serve({ fetch: app.fetch, hostname: '127.0.0.1', port: 18790 }, () => console.log('Browser UI fixture ready on 127.0.0.1:18790'));
async function stop() {
  worker.stop();
  await browser.closeAll();
  server.close();
  await database.database.close();
  process.exit(0);
}
process.once('SIGINT', () => void stop());
process.once('SIGTERM', () => void stop());
