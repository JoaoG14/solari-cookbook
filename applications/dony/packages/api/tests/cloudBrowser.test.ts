import { EventEmitter } from 'node:events';
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
  const cdp = Object.assign(new EventEmitter(), {
    send: vi.fn().mockResolvedValue(undefined), detach: vi.fn().mockResolvedValue(undefined)
  });
  const context = { newCDPSession: vi.fn().mockResolvedValue(cdp) };
  const page = {
    context: () => context,
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
  return { page, browser, client, cdp, context, create: () => client as unknown as Pick<Solari, 'launch' | 'close'> };
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

it('shares a live screencast, acknowledges frames, and stops when the last viewer leaves', async () => {
  await service.act(job, { action: 'open', url: 'https://example.com' }, signal);
  const first = vi.fn(); const second = vi.fn();
  const [stopFirst, stopSecond] = await Promise.all([service.watch(job, first), service.watch(job, second)]);
  expect(fake.context.newCDPSession).toHaveBeenCalledTimes(1);
  for (let i = 0; i < 3; i++) fake.cdp.emit('Page.screencastFrame', { data: `frame${i}`, sessionId: i });
  expect(first).toHaveBeenLastCalledWith(expect.objectContaining({ image: 'frame2', status: 'active' }));
  expect(second).toHaveBeenCalledTimes(3);
  expect(fake.cdp.send).toHaveBeenCalledWith('Page.screencastFrameAck', { sessionId: 2 });
  expect(fake.page.screenshot).not.toHaveBeenCalled();
  await stopFirst();
  expect(fake.cdp.detach).not.toHaveBeenCalled();
  await stopSecond();
  expect(fake.cdp.send).toHaveBeenCalledWith('Page.stopScreencast');
  expect(fake.cdp.detach).toHaveBeenCalledTimes(1);
  expect(fake.browser.close).not.toHaveBeenCalled();
});

it('ends all viewers on run completion and ignores late frames', async () => {
  await service.act(job, { action: 'open', url: 'https://example.com' }, signal);
  const receive = vi.fn();
  const stop = await service.watch(job, receive);
  await service.close(job);
  fake.cdp.emit('Page.screencastFrame', { data: 'late', sessionId: 1 });
  expect(receive).toHaveBeenLastCalledWith({ status: 'inactive' });
  expect(receive).not.toHaveBeenCalledWith(expect.objectContaining({ image: 'late' }));
  await stop();
});

it('reports stream failure without leaking provider credentials and can reconnect', async () => {
  await service.act(job, { action: 'open', url: 'https://example.com' }, signal);
  fake.cdp.send.mockRejectedValueOnce(new Error('wss://secret-provider-token'));
  await expect(service.watch(job, vi.fn())).rejects.toThrow('Browser streaming is temporarily unavailable.');
  const receive = vi.fn();
  const stop = await service.watch(job, receive);
  fake.cdp.emit('close');
  expect(receive).toHaveBeenLastCalledWith({ status: 'error' });
  await stop();
});

it('authenticates streams and blocks canceled leases before sending queued frames', async () => {
  await service.act(job, { action: 'open', url: 'https://example.com' }, signal);
  const routes = createMobileRoutes(store, async headers => {
    const id = headers.get('authorization')?.replace('Bearer ', '');
    return id ? { id, name: null, email: null, avatarUrl: null } : Response.json({}, { status: 401 });
  }, true, connectors, undefined, undefined, service);
  const path = `/threads/${job.thread_id}/browser/stream`;
  expect((await routes.request(path)).status).toBe(401);
  const other = await routes.request(path, { headers: { authorization: 'Bearer bob' } });
  expect(await other.text()).toContain('"status":"inactive"');
  expect(fake.context.newCDPSession).not.toHaveBeenCalled();
  const response = await routes.request(path, { headers: { authorization: 'Bearer alice' } });
  expect(response.headers.get('cache-control')).toBe('no-store');
  expect(response.headers.get('content-type')).toBe('text/event-stream');
  const reader = response.body!.getReader();
  const read = async () => new TextDecoder().decode((await reader.read()).value);
  expect(await read()).toContain('heartbeat');
  fake.cdp.emit('Page.screencastFrame', { data: 'live', sessionId: 1 });
  expect(await read()).toContain('"image":"live"');
  await store.pool.query("UPDATE cloud_jobs SET state = 'canceled' WHERE id = $1", [job.id]);
  fake.cdp.emit('Page.screencastFrame', { data: 'must-not-deliver', sessionId: 2 });
  const last = await read();
  expect(last).toContain('inactive');
  expect(last).not.toContain('must-not-deliver');
  await reader.cancel();
  await vi.waitFor(() => expect(fake.cdp.detach).toHaveBeenCalled());
});

it('releases a stream on disconnect without closing the agent browser', async () => {
  await service.act(job, { action: 'open', url: 'https://example.com' }, signal);
  const routes = createMobileRoutes(store, async () => ({ id: 'alice', name: null, email: null, avatarUrl: null }), true, connectors, undefined, undefined, service);
  const response = await routes.request(`/threads/${job.thread_id}/browser/stream`);
  const reader = response.body!.getReader();
  await reader.read();
  await reader.cancel();
  await vi.waitFor(() => expect(fake.cdp.detach).toHaveBeenCalled());
  expect(fake.browser.close).not.toHaveBeenCalled();
});

it('drops superseded frames and ends an already-open stream when authentication is revoked', async () => {
  await service.act(job, { action: 'open', url: 'https://example.com' }, signal);
  let revoked = false;
  const routes = createMobileRoutes(store, async () => revoked ? Response.json({}, { status: 401 }) :
    ({ id: 'alice', name: null, email: null, avatarUrl: null }), true, connectors, undefined, undefined, service);
  const response = await routes.request(`/threads/${job.thread_id}/browser/stream`);
  const reader = response.body!.getReader();
  await reader.read();
  for (let i = 0; i < 100; i++) fake.cdp.emit('Page.screencastFrame', { data: `frame${i}`, sessionId: i });
  const data = new TextDecoder().decode((await reader.read()).value);
  expect(data).toContain('"image":"frame99"');
  expect(data).not.toContain('"image":"frame0"');
  revoked = true;
  while (!(await reader.read()).done) { /* consume the last heartbeat before revocation */ }
  await vi.waitFor(() => expect(fake.cdp.detach).toHaveBeenCalled());
});
