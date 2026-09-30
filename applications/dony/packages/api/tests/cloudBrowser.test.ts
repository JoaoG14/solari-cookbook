import { randomUUID } from 'node:crypto';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import type { BrowserSession, Solari } from '@solarisdk/browser';
import { CloudBrowser } from '../src/cloudBrowser';
import { CloudWorker } from '../src/cloudWorker';
import { CloudStore, type CloudJob } from '../src/cloudStore';
import { createMobileRoutes } from '../src/mobileRoutes';
import type { composioConnectorService } from '../src/composioConnectorService';
import type { CloudModel } from '../src/cloudModel';
import { companionTestDatabase } from './helpers/companionDatabase';

function fakeClient() {
  const page = {
    setDefaultTimeout: vi.fn(), setDefaultNavigationTimeout: vi.fn(),
    goto: vi.fn().mockResolvedValue(undefined), url: () => 'https://example.com/',
    title: async () => 'Example', screenshot: vi.fn().mockResolvedValue(Buffer.from('frame')),
    locator: () => ({ ariaSnapshot: async () => '- heading "Example"' }),
    getByRole: vi.fn(() => ({ click: vi.fn().mockResolvedValue(undefined) })),
    getByLabel: vi.fn(() => ({ fill: vi.fn().mockResolvedValue(undefined) })),
    keyboard: { press: vi.fn() }, mouse: { wheel: vi.fn() }
  };
  const browser = { newContext: async () => ({ newPage: async () => page }), close: vi.fn().mockResolvedValue(undefined) };
  const client = { launch: vi.fn().mockResolvedValue(browser), close: vi.fn().mockResolvedValue(undefined) };
  return { page, browser, client, create: () => client as unknown as Pick<Solari, 'launch' | 'close'> };
}
let database: Awaited<ReturnType<typeof companionTestDatabase>>;
let store: CloudStore;
let service: CloudBrowser;
let fake: ReturnType<typeof fakeClient>;
let job: CloudJob;
const connectors = { execute: async () => ({}) } as unknown as typeof composioConnectorService;
const signal = new AbortController().signal;
beforeEach(async () => {
  database = await companionTestDatabase();
  store = new CloudStore(database.pool);
  await store.migrate();
  await store.settings('alice', { pro: true });
  const workspace = await store.workspace(store.pool, 'alice');
  const threadId = randomUUID();
  await store.command('alice', { id: randomUUID(), executionTarget: 'cloud', action: { type: 'chat.create', threadId, agentId: workspace.snapshot.agents[0]!.id } });
  await store.command('alice', { id: randomUUID(), executionTarget: 'cloud', action: { type: 'chat.send', threadId, message: 'Read example.com', files: [] } });
  job = (await store.claim())!;
  fake = fakeClient();
  service = new CloudBrowser('test-key', fake.create);
});
afterEach(async () => {
  await service.close(job);
  await database.database.close();
});

it('opens one isolated session, reads page evidence, and coalesces screenshots', async () => {
  const result = await service.act(job, { action: 'open', url: 'https://example.com' }, signal);
  expect(result).toMatchObject({ title: 'Example', content: '- heading "Example"' });
  await service.act(job, { action: 'click', role: 'link', name: 'More' }, signal);
  expect(fake.page.getByRole).toHaveBeenCalledWith('link', { name: 'More', exact: true });
  expect(fake.client.launch).toHaveBeenCalledTimes(1);
  const previews = await Promise.all([service.preview(job), service.preview(job)]);
  expect(previews[0]).toMatchObject({ status: 'active', image: Buffer.from('frame').toString('base64') });
  expect(previews[1]).toEqual(previews[0]);
  await service.preview(job);
  expect(fake.page.screenshot).toHaveBeenCalledTimes(1);
  expect(service.activeJob('bob', job.thread_id)).toBeUndefined();
  expect(service.activeJob('alice', 'another-thread')).toBeUndefined();
});

it('authenticates previews, hides other users, and stops serving canceled runs', async () => {
  await service.act(job, { action: 'open', url: 'https://example.com' }, signal);
  const routes = createMobileRoutes(store, async (headers) => {
    const id = headers.get('authorization')?.replace('Bearer ', '');
    return id ? { id, name: null, email: null, avatarUrl: null } : Response.json({}, { status: 401 });
  }, true, connectors, undefined, undefined, service);
  const path = `/threads/${job.thread_id}/browser`;
  expect((await routes.request(path)).status).toBe(401);
  expect(await (await routes.request(path, { headers: { authorization: 'Bearer bob' } })).json()).toEqual({ status: 'inactive' });
  const own = await routes.request(path, { headers: { authorization: 'Bearer alice' } });
  expect(own.headers.get('cache-control')).toBe('no-store');
  expect(await own.json()).toMatchObject({ status: 'active' });
  await store.pool.query("UPDATE cloud_jobs SET state = 'canceled' WHERE id = $1", [job.id]);
  expect(await (await routes.request(path, { headers: { authorization: 'Bearer alice' } })).json()).toEqual({ status: 'inactive' });
  expect((await routes.request(path, { method: 'POST', headers: { authorization: 'Bearer alice' } })).status).toBe(404);
});

it('rejects unsafe URLs and hides raw provider errors', async () => {
  await expect(service.act(job, { action: 'open', url: 'file:///etc/passwd' }, signal)).rejects.toThrow('HTTP');
  await expect(service.act(job, { action: 'open', url: 'https://user:password@example.com' }, signal)).rejects.toThrow('credentials');
  expect(fake.client.launch).not.toHaveBeenCalled();
  fake.page.goto.mockRejectedValue(new Error('wss://secret-provider-token'));
  expect(JSON.stringify(await service.act(job, { action: 'open', url: 'https://example.com' }, signal))).not.toContain('secret-provider-token');
});

it.each(['completed', 'failed', 'blocked', 'stopped'] as const)('releases the browser and proxy when a run is %s', async (ending) => {
  let worker: CloudWorker;
  const model: CloudModel = { configured: true, step: async (_job, input) => {
    await input.tools.browser_use!.execute!({ action: 'open', url: 'https://example.com' }, { toolCallId: 'browse', messages: [] });
    expect(service.activeJob('alice', job.thread_id)?.id).toBe(job.id);
    if (ending === 'failed') throw new Error('model failed');
    if (ending === 'blocked') await input.tools.ask_user!.execute!({ question: 'Continue?', options: ['Yes'] }, { toolCallId: 'ask', messages: [] });
    if (ending === 'stopped') { worker.stop(); input.signal.throwIfAborted(); }
    return { messages: [], text: 'Done', finished: true };
  } };
  worker = new CloudWorker(store, model, connectors, service);
  await worker.run(job);
  expect(fake.browser.close).toHaveBeenCalledTimes(1);
  expect(fake.client.close).toHaveBeenCalledTimes(1);
  expect(await service.preview(job)).toEqual({ status: 'inactive' });
  expect(service.activeJob('alice', job.thread_id)).toBeUndefined();
});

it('awaits a pending launch during cleanup and uses a fresh browser on resume', async () => {
  let resolveLaunch!: (value: BrowserSession) => void;
  fake.client.launch.mockImplementationOnce(() => new Promise(resolve => { resolveLaunch = resolve; }));
  const controller = new AbortController();
  const opening = service.act(job, { action: 'open', url: 'https://example.com' }, controller.signal);
  controller.abort();
  const closing = service.close(job);
  resolveLaunch(fake.browser as unknown as BrowserSession);
  await expect(opening).rejects.toThrow();
  await closing;
  expect(fake.page.goto).not.toHaveBeenCalled();
  expect(fake.browser.close).toHaveBeenCalledTimes(1);
  expect(await service.act(job, { action: 'read' }, signal)).toHaveProperty('error');
  await service.act({ ...job, lease: 'new-lease' }, { action: 'open', url: 'https://example.com' }, signal);
  expect(fake.client.launch).toHaveBeenCalledTimes(2);
  await service.close({ ...job, lease: 'new-lease' });
});
