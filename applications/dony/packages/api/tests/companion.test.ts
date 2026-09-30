import { createHash, randomUUID } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { CompanionCommand, CompanionSnapshot } from '@dony/domain';
import { CompanionStore } from '../src/companionStore';
import { createCompanionRoutes } from '../src/companionRoutes';
import { companionTestDatabase } from './helpers/companionDatabase';

const snapshot: CompanionSnapshot = {
  version: 1,
  mode: 'off',
  tasks: [],
  agents: [],
  threads: [],
  results: []
};
const command = (): CompanionCommand => ({
  id: randomUUID(),
  action: {
    type: 'task.create',
    taskId: randomUUID(),
    input: { title: 'Prepare the weekly update' }
  }
});

describe('mobile companion relay', () => {
  let db: Awaited<ReturnType<typeof companionTestDatabase>>;
  let store: CompanionStore;
  let desktopId: string;
  let pairing: Awaited<ReturnType<CompanionStore['pair']>>;
  beforeAll(async () => {
    db = await companionTestDatabase();
    store = new CompanionStore(db.pool);
    await store.migrate();
  }, 30_000);
  afterAll(async () => {
    await db.database.close();
  });
  beforeEach(async () => {
    await db.pool.query('DELETE FROM companion_desktops');
    desktopId = randomUUID();
    await store.register('owner', desktopId, 'Work Mac');
    const { code } = await store.pairCode('owner', desktopId);
    pairing = await store.pair(code, 'iPhone');
  });

  it('mirrors local pairing credentials, checks paid access and never resurrects revoked phones', async () => {
    let paid = false;
    const gated = new CompanionStore(db.pool, {
      status: async () => ({ canUseRemoteDesktop: paid })
    } as import('../src/billing/store').BillingStore);
    const token = 'locally-issued-phone-secret';
    const device = { id: randomUUID(), name: 'Local phone', tokenHash: createHash('sha256').update(token).digest('hex') };
    await gated.syncDevices('owner', desktopId, [device]);
    const phone = await gated.device(token);
    await expect(gated.state(phone, -1, [])).rejects.toMatchObject({ status: 403 });
    await expect(gated.submit(phone, command())).rejects.toMatchObject({ status: 403 });
    await expect(gated.exchange('owner', desktopId, snapshot, [])).rejects.toMatchObject({ status: 403 });
    await expect(gated.syncDevices('other', desktopId, [device])).rejects.toMatchObject({ status: 404 });
    paid = true;
    const queued = command();
    await gated.submit(phone, queued);
    expect(await gated.exchange('owner', desktopId, snapshot, [])).toEqual([queued]);
    await gated.exchange('owner', desktopId, snapshot, [{ id: queued.id, status: 'completed' }]);
    expect((await gated.state(phone, -1, [queued.id])).receipts).toEqual([{ id: queued.id, status: 'completed' }]);
    paid = false;
    await expect(gated.state(phone, -1, [])).rejects.toMatchObject({ status: 403 });
    await gated.syncDevices('owner', desktopId, []);
    await gated.syncDevices('owner', desktopId, [device]);
    await expect(gated.device(token)).rejects.toMatchObject({ status: 401 });
  });

  it('pairs only once, expires codes, and requires the desktop owner', async () => {
    const { code } = await store.pairCode('owner', desktopId);
    await expect(
      store.pairCode('other-account', desktopId)
    ).rejects.toMatchObject({ status: 404 });
    await expect(
      store.register('other-account', desktopId, 'Other Mac')
    ).rejects.toMatchObject({ status: 404 });
    expect((await store.pair(code, 'Second phone')).accountId).toBe('owner');
    await expect(store.pair(code, 'Third phone')).rejects.toMatchObject({
      status: 410
    });
    const next = await store.pairCode('owner', desktopId);
    await db.pool.query(
      "UPDATE companion_pairings SET expires_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-1 second')"
    );
    await expect(store.pair(next.code, 'Phone')).rejects.toMatchObject({
      status: 410
    });
    const row = (
      await db.pool.query(
        'SELECT token_hash FROM companion_devices WHERE id = $1',
        [pairing.deviceId]
      )
    ).rows[0] as { token_hash: string };
    expect(row.token_hash).not.toBe(pairing.token);
  });

  it('keeps ordered commands while the desktop is offline and deduplicates identical delivery', async () => {
    const phone = await store.device(pairing.token);
    expect((await store.state(phone, -1, [])).desktopOnline).toBe(false);
    const first = command();
    const second = command();
    await store.submit(phone, first);
    await store.submit(phone, first);
    await store.submit(phone, second);
    const pending = await store.exchange('owner', desktopId, snapshot, []);
    expect(pending.map((item) => item.id)).toEqual([first.id, second.id]);
    await expect(
      store.submit(phone, {
        ...first,
        action: {
          ...first.action,
          type: 'mode.set',
          mode: 'proactive',
          expectedMode: 'off'
        }
      })
    ).rejects.toMatchObject({ status: 409 });
    expect((await store.state(phone, -1, [])).desktopOnline).toBe(true);
  });

  it('keeps idle relay heartbeats online between thirty-second exchanges', async () => {
    const phone = await store.device(pairing.token);
    await store.exchange('owner', desktopId, snapshot, []);
    await db.pool.query("UPDATE companion_desktops SET last_seen_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-45 seconds') WHERE id = $1", [desktopId]);
    expect((await store.state(phone, -1, [])).desktopOnline).toBe(true);
    await db.pool.query("UPDATE companion_desktops SET last_seen_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-90 seconds') WHERE id = $1", [desktopId]);
    expect((await store.state(phone, -1, [])).desktopOnline).toBe(false);
  });

  it('publishes state with receipts and isolates acknowledgements between phones', async () => {
    const phone = await store.device(pairing.token);
    const queued = command();
    await store.submit(phone, queued);
    const receipt = {
      id: queued.id,
      status: 'completed' as const,
      error: null
    };
    await store.exchange('owner', desktopId, { ...snapshot, mode: 'suggest' }, [
      receipt
    ]);
    const state = await store.state(phone, -1, [queued.id]);
    expect(state.snapshot?.mode).toBe('suggest');
    expect(state.receipts).toEqual([receipt]);
    expect((await store.state(phone, state.revision, [])).snapshot).toBeNull();
    expect(await store.exchange('owner', desktopId, undefined, [])).toEqual([]);
    const next = await store.pairCode('owner', desktopId);
    const other = await store.pair(next.code, 'Another phone');
    expect(
      (await store.state(await store.device(other.token), -1, [queued.id]))
        .receipts
    ).toEqual([]);
    await expect(
      store.submit(await store.device(other.token), queued)
    ).rejects.toMatchObject({ status: 409 });
  });

  it('revokes access and cancels work that has not reached the desktop', async () => {
    const phone = await store.device(pairing.token);
    const queued = command();
    await store.submit(phone, queued);
    await store.revoke('owner', desktopId, phone.id);
    await expect(store.device(pairing.token)).rejects.toMatchObject({
      status: 401
    });
    await expect(store.submit(phone, command())).rejects.toMatchObject({
      status: 401
    });
    expect(await store.exchange('owner', desktopId, snapshot, [])).toEqual([]);
    await store.disconnect('owner', desktopId);
    await expect(store.desktop('owner', desktopId)).rejects.toMatchObject({
      status: 404
    });
  });

  it('exposes only the companion command surface to a phone credential', async () => {
    const routes = createCompanionRoutes(store, async (headers) =>
      headers.get('authorization') === 'Bearer desktop-session'
        ? { id: 'owner', name: null, email: null, avatarUrl: null }
        : new Response(null, { status: 401 })
    );
    const headers = {
      authorization: `Bearer ${pairing.token}`,
      'content-type': 'application/json'
    };
    const invoke = (url: string, value: unknown) =>
      routes.request(url, {
        method: 'POST',
        headers,
        body: JSON.stringify(value)
      });
    expect(
      (await invoke('/desktops', { id: randomUUID(), name: 'Injected' })).status
    ).toBe(401);
    expect(
      (
        await invoke('/commands', {
          id: randomUUID(),
          action: { type: 'terminal.open', path: '/tmp' }
        })
      ).status
    ).toBe(400);
    expect((await invoke('/commands', command())).status).toBe(200);
    expect(
      (await invoke('/state', { revision: -1, commandIds: [] })).status
    ).toBe(200);
  });
});

it('restores the snapshot and queued work after the backend restarts', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'dony-companion-pg-'));
  let db = await companionTestDatabase(directory);
  try {
    let store = new CompanionStore(db.pool);
    await store.migrate();
    const desktopId = randomUUID();
    await store.register('owner', desktopId, 'Mac');
    const { code } = await store.pairCode('owner', desktopId);
    const pairing = await store.pair(code, 'iPhone');
    const queued = command();
    await store.submit(await store.device(pairing.token), queued);
    await store.exchange('owner', desktopId, snapshot, []);
    await db.database.close();
    db = await companionTestDatabase(directory);
    store = new CompanionStore(db.pool);
    expect(
      (await store.state(await store.device(pairing.token), -1, [])).snapshot
    ).toEqual(snapshot);
    expect(
      (await store.exchange('owner', desktopId, undefined, [])).map(
        (item) => item.id
      )
    ).toEqual([queued.id]);
  } finally {
    await db.database.close();
    await rm(directory, { recursive: true, force: true });
  }
}, 30_000);
