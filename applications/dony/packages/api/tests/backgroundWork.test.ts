import { randomUUID } from 'node:crypto';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { WorkLoop } from '../src/workLoop';
import { CloudRecovery, CLOUD_RECOVERY_INTERVAL_MS } from '../src/cloudRecovery';
import { CloudStore } from '../src/cloudStore';
import { CloudWorker } from '../src/cloudWorker';
import { CloudPush } from '../src/cloudPush';
import type { DonyDatabase } from '../src/database';
import { companionTestDatabase } from './helpers/companionDatabase';

afterEach(() => vi.useRealTimers());

it('coalesces busy wakes, drains remaining work, and stays idle without polling', async () => {
  vi.useFakeTimers();
  let release!: (more: boolean) => void;
  const tick = vi.fn().mockImplementationOnce(() => new Promise<boolean>((resolve) => { release = resolve; }))
    .mockResolvedValueOnce(true).mockResolvedValue(false);
  const loop = new WorkLoop(tick);
  loop.start();
  loop.wake();
  loop.wake();
  expect(tick).toHaveBeenCalledTimes(1);
  release(false);
  await vi.advanceTimersByTimeAsync(0);
  expect(tick).toHaveBeenCalledTimes(3);
  await vi.advanceTimersByTimeAsync(30 * 60_000);
  expect(tick).toHaveBeenCalledTimes(3);
  loop.stop();
  loop.wake();
  expect(tick).toHaveBeenCalledTimes(3);
});

it('runs recovery every five minutes and cancels it on shutdown', async () => {
  vi.useFakeTimers();
  const query = vi.fn().mockResolvedValue({ rows: [{ id: 'background' }] });
  const wake = vi.fn();
  const recovery = new CloudRecovery({ query } as unknown as DonyDatabase, wake);
  recovery.start();
  recovery.start();
  await vi.advanceTimersByTimeAsync(CLOUD_RECOVERY_INTERVAL_MS - 1);
  expect(query).not.toHaveBeenCalled();
  await vi.advanceTimersByTimeAsync(1);
  expect(wake).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(CLOUD_RECOVERY_INTERVAL_MS);
  expect(wake).toHaveBeenCalledTimes(2);
  recovery.stop();
  await vi.advanceTimersByTimeAsync(CLOUD_RECOVERY_INTERVAL_MS);
  expect(wake).toHaveBeenCalledTimes(2);
});

it('drains more than one notification batch on startup without waiting five minutes', async () => {
  const notifications = Array.from({ length: 25 }, (_, id) => ({ id: String(id), workspace_id: 'w', thread_id: 't', title: 'Done', body: 'Done' }));
  const query = vi.fn(async (sql: string, params?: string[]) => {
    if (sql.startsWith('SELECT n.')) return { rows: notifications.slice(0, 20) };
    if (sql.startsWith('SELECT token')) return { rows: [] };
    if (sql.includes('UPDATE cloud_notifications')) notifications.splice(notifications.findIndex((n) => n.id === params![0]), 1);
    return { rows: [] };
  });
  const push = new CloudPush({ query } as unknown as DonyDatabase, { keyId: 'unused', teamId: 'unused', privateKey: 'unused', topic: 'unused' });
  push.start();
  await vi.waitFor(() => expect(notifications).toHaveLength(0));
  push.stop();
  expect(query.mock.calls.filter(([sql]) => sql.startsWith('SELECT n.'))).toHaveLength(2);
});

describe('durable work through the real D1 gateway', () => {
  it('backfills pre-existing workspaces once and preserves pending work across startup', async () => {
    const db = await companionTestDatabase();
    try {
      const store = new CloudStore(db.pool);
      await store.migrate();
      await store.settings('alice', { pro: true });
      // Recreate the pre-upgrade state while retaining the existing workspace.
      await db.pool.query('DROP TABLE cloud_planning_pending');
      await db.pool.query('DROP TABLE cloud_recovery');
      await store.migrate();
      expect((await db.pool.query('SELECT * FROM cloud_planning_pending')).rows).toHaveLength(1);
      await store.migrate();
      expect((await db.pool.query('SELECT * FROM cloud_planning_pending')).rows).toHaveLength(1);
      await db.pool.query('DELETE FROM cloud_planning_pending');
      await store.migrate();
      expect((await db.pool.query('SELECT * FROM cloud_planning_pending')).rows).toHaveLength(0);
    } finally { await db.database.close(); }
  });

  it('elects only one recovery scanner across backend instances', async () => {
    const db = await companionTestDatabase();
    try {
      await new CloudStore(db.pool).migrate();
      const wake = vi.fn();
      const a = new CloudRecovery(db.pool, wake);
      const b = new CloudRecovery(db.pool, wake);
      await Promise.all([a.check(), b.check()]);
      expect(wake).toHaveBeenCalledTimes(1);
      await db.pool.query("UPDATE cloud_recovery SET next_check_at = 0 WHERE id = 'background'");
      await b.check();
      expect(wake).toHaveBeenCalledTimes(2);
    } finally { await db.database.close(); }
  });

  it('signals only committed changes, ignores unchanged planning inputs, and retains missed work', async () => {
    const db = await companionTestDatabase();
    try {
      const store = new CloudStore(db.pool);
      await store.migrate();
      const wake = vi.fn();
      store.onWorkAvailable = wake;
      await store.settings('alice', { pro: true });
      expect(wake).toHaveBeenCalledTimes(1);
      const worker = new CloudWorker(store, { configured: true, step: vi.fn() }, { execute: vi.fn() });
      await worker.schedulePlans();
      await store.edit('alice', () => {});
      expect(wake).toHaveBeenCalledTimes(1);
      await expect(store.transaction(async (client) => {
        const workspace = await store.workspace(client, 'alice');
        workspace.snapshot.mode = 'suggest';
        await store.save(client, workspace);
        throw new Error('rollback');
      })).rejects.toThrow('rollback');
      expect(wake).toHaveBeenCalledTimes(1);
      expect((await db.pool.query('SELECT * FROM cloud_planning_pending')).rows).toHaveLength(0);
      // Simulate losing the signal after a successful commit.
      store.onWorkAvailable = () => {};
      await store.edit('alice', (snapshot) => { snapshot.mode = 'suggest'; });
      expect((await db.pool.query('SELECT * FROM cloud_planning_pending')).rows).toHaveLength(1);
      const restored = new CloudStore(db.pool);
      await new CloudWorker(restored, { configured: true, step: vi.fn() }, { execute: vi.fn() }).schedulePlans();
      expect((await db.pool.query('SELECT * FROM cloud_planning_pending')).rows).toHaveLength(0);
    } finally { await db.database.close(); }
  });

  it('processes newly committed jobs immediately and emits notification wakes', async () => {
    const db = await companionTestDatabase();
    const store = new CloudStore(db.pool);
    const worker = new CloudWorker(store, {
      configured: true,
      step: async (_job, input) => ({ text: 'Finished', messages: input.messages, finished: true })
    }, { execute: vi.fn() });
    try {
      await store.migrate();
      await store.settings('alice', { pro: true });
      const snapshot = (await store.state('alice', -1, [])).snapshot!;
      const threadId = randomUUID();
      await store.command('alice', { id: randomUUID(), executionTarget: 'cloud', action: { type: 'chat.create', threadId, agentId: snapshot.agents[0]!.id } });
      store.onWorkAvailable = () => worker.wake();
      const notified = vi.fn();
      store.onNotificationsAvailable = notified;
      worker.start();
      await store.command('alice', { id: randomUUID(), executionTarget: 'cloud', action: { type: 'chat.send', threadId, message: 'Hello', files: [] } });
      await vi.waitFor(async () => {
        expect((await db.pool.query("SELECT id FROM cloud_jobs WHERE state = 'completed'")).rows).toHaveLength(1);
        expect(notified).toHaveBeenCalledTimes(1);
      });
      await new Promise((resolve) => setTimeout(resolve, 30));
      store.onWorkAvailable = () => {}; // A crash/lost local signal after commit.
      await store.command('alice', { id: randomUUID(), executionTarget: 'cloud', action: { type: 'chat.send', threadId, message: 'Again', files: [] } });
      expect((await db.pool.query("SELECT id FROM cloud_jobs WHERE state = 'queued'")).rows).toHaveLength(1);
      await new CloudRecovery(db.pool, () => worker.wake()).check();
      await vi.waitFor(async () => {
        expect((await db.pool.query("SELECT id FROM cloud_jobs WHERE state = 'completed'")).rows).toHaveLength(2);
        expect(notified).toHaveBeenCalledTimes(2);
      });
    } finally {
      worker.stop();
      // Let any final, already in-flight claim finish before disposing D1.
      await new Promise((resolve) => setTimeout(resolve, 30));
      await db.database.close();
    }
  });
});
