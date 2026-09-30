import { afterEach, expect, it, vi } from 'vitest';
import { WorkspaceChanges, SYNC_RECOVERY_MS } from '../src/workspaceChanges';

afterEach(() => vi.useRealTimers());

it('waits without polling and wakes only the changed account', async () => {
  vi.useFakeTimers();
  const changes = new WorkspaceChanges();
  const controller = new AbortController();
  const initial = await changes.wait('alice', undefined, controller.signal);
  const done = vi.fn();
  const pending = changes.wait('alice', initial.cursor, controller.signal).then(done);
  changes.publish('bob');
  await vi.advanceTimersByTimeAsync(SYNC_RECOVERY_MS - 1);
  expect(done).not.toHaveBeenCalled();
  changes.publish('alice');
  await pending;
  expect(done).toHaveBeenCalledWith(expect.objectContaining({ cursor: expect.not.stringMatching(initial.cursor) }));
  expect(vi.getTimerCount()).toBe(0);
});

it('reconciles after missed changes, restart, timeout, and cancellation', async () => {
  vi.useFakeTimers();
  const changes = new WorkspaceChanges();
  const controller = new AbortController();
  const first = await changes.wait('alice', undefined, controller.signal);
  changes.publish('alice');
  const missed = await changes.wait('alice', first.cursor, controller.signal);
  expect(missed.cursor).not.toBe(first.cursor);
  const timed = changes.wait('alice', missed.cursor, controller.signal);
  await vi.advanceTimersByTimeAsync(SYNC_RECOVERY_MS);
  expect(await timed).toEqual(missed);
  const canceled = changes.wait('alice', missed.cursor, controller.signal);
  controller.abort();
  expect(await canceled).toEqual(missed);
  expect(vi.getTimerCount()).toBe(0);
  const restarted = new WorkspaceChanges();
  expect(await restarted.wait('alice', missed.cursor, new AbortController().signal)).not.toEqual(missed);
});
