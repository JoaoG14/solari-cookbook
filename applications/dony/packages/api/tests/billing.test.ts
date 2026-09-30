import { randomUUID } from 'node:crypto';
import { afterEach, beforeEach, expect, it } from 'vitest';
import { companionTestDatabase } from './helpers/companionDatabase';
import { CloudStore } from '../src/cloudStore';
import { BillingStore, type VerifiedPurchase } from '../src/billing/store';
import { addMonths } from '../src/billing/catalog';

let db: Awaited<ReturnType<typeof companionTestDatabase>>;
let billing: BillingStore;
let cloud: CloudStore;
let now: number;
let token: string;
beforeEach(async () => {
  now = Date.parse('2026-01-31T12:00:00Z');
  db = await companionTestDatabase();
  billing = new BillingStore(db.pool, true, () => now);
  cloud = new CloudStore(db.pool, billing);
  await cloud.migrate();
  await billing.migrate();
  token = await billing.account('alice');
});
afterEach(async () => {
  await db.database.close();
});
function purchase(
  product = 'pro.monthly',
  values: Partial<VerifiedPurchase> = {}
): VerifiedPurchase {
  const id = randomUUID();
  return {
    id,
    originalId: id,
    accountToken: token,
    productId: `com.dony.solari.mobile.${product}`,
    purchasedAt: now,
    expiresAt: addMonths(now, product.endsWith('yearly') ? 12 : 1),
    signedAt: now,
    revokedAt: null,
    upgraded: false,
    ...values
  };
}
async function spend(amount: number, job = randomUUID()) {
  const id = randomUUID();
  await db.pool.transaction((client) =>
    billing.reserve(client, 'alice', job, id, amount)
  );
  return id;
}
it('keeps the basic list free and rejects the old self-service Pro switch', async () => {
  expect((await billing.status('alice')).canRunCloud).toBe(false);
  await expect(cloud.settings('alice', { pro: true })).rejects.toThrow(
    'Manage your subscription'
  );
  await cloud.command('alice', {
    id: randomUUID(),
    executionTarget: 'cloud',
    action: {
      type: 'task.create',
      taskId: randomUUID(),
      input: { title: 'A free to-do' }
    }
  });
  expect((await cloud.state('alice', -1, [])).snapshot?.tasks[0]?.title).toBe(
    'A free to-do'
  );
  await expect(spend(1)).rejects.toThrow('Choose a plan');
});
it('deduplicates restores, rejects cross-account claims, and never exposes provider costs', async () => {
  const p = purchase();
  await billing.apply(p, 'alice');
  await billing.apply(p, 'alice');
  await spend(1_000_000);
  await billing.apply({ ...p, signedAt: now + 1 }, 'alice');
  const status = await billing.status('alice');
  expect(status.monthlyUsedPercent).toBeCloseTo(100 / 7);
  expect(status).not.toHaveProperty('allowance');
  expect(status).not.toHaveProperty('remaining');
  await expect(billing.apply(p, 'bob')).rejects.toThrow('another Dony account');
});
it('resets annual allowance monthly without short-month anniversary drift', async () => {
  await billing.apply(purchase('pro.yearly'));
  await spend(3_000_000);
  expect((await billing.status('alice')).resetsAt).toBe(
    '2026-02-28T12:00:00.000Z'
  );
  now = Date.parse('2026-02-28T12:00:00Z');
  expect((await billing.status('alice')).monthlyUsedPercent).toBe(0);
  expect((await billing.status('alice')).resetsAt).toBe(
    '2026-03-31T12:00:00.000Z'
  );
  now = Date.parse('2027-01-31T12:00:00Z');
  expect((await billing.status('alice')).canRunCloud).toBe(false);
});
it('consumes monthly allowance first and preserves extras after expiration and upgrades', async () => {
  await billing.apply(purchase());
  const extra = purchase('extra.20', { expiresAt: null });
  await billing.apply(extra);
  await billing.apply(extra);
  await spend(3_000_000);
  await spend(3_000_000);
  await spend(2_000_000);
  expect((await billing.status('alice')).monthlyUsedPercent).toBe(100);
  expect((await billing.status('alice')).extraRemainingPercent).toBeCloseTo(
    600 / 7
  );
  now = addMonths(now, 2);
  expect((await billing.status('alice')).canRunCloud).toBe(true);
  await billing.apply(purchase('plus.monthly'));
  expect((await billing.status('alice')).extraRemainingPercent).toBeCloseTo(
    600 / 35
  );
});
it('does not double-spend concurrent reservations and releases only verified unused cost', async () => {
  await billing.apply(purchase());
  await spend(3_000_000);
  await spend(3_000_000);
  const results = await Promise.allSettled([spend(750_000), spend(750_000)]);
  expect(
    results.filter((result) => result.status === 'fulfilled')
  ).toHaveLength(1);
  const id = (
    results.find(
      (result) => result.status === 'fulfilled'
    ) as PromiseFulfilledResult<string>
  ).value;
  await db.pool.transaction((client) => billing.settle(client, id, 250_000));
  await db.pool.transaction((client) => billing.settle(client, id, 0));
  expect((await billing.status('alice')).monthlyUsedPercent).toBeCloseTo(
    625 / 7
  );
});
it('refunds revoke credits and stale restores cannot resurrect them', async () => {
  const p = purchase('extra.50', { expiresAt: null });
  await billing.apply(p);
  expect((await billing.status('alice')).extraRemainingPercent).toBe(250);
  await billing.apply({ ...p, revokedAt: now + 1, signedAt: now + 1 });
  await billing.apply(p);
  expect((await billing.status('alice')).canRunCloud).toBe(false);
});
it('caps total account usage and allows the full allowance in one task', async () => {
  await billing.apply(purchase());
  await spend(7_000_000);
  await expect(spend(1)).rejects.toThrow('used this month');
  expect((await billing.status('alice')).limitReached).toBe(true);
});
it('restores access after a current Apple refund reversal', async () => {
  const p = purchase();
  await billing.apply(p);
  await billing.apply({ ...p, revokedAt: now + 1, signedAt: now + 1 });
  expect((await billing.status('alice')).canRunCloud).toBe(false);
  await billing.apply({ ...p, signedAt: now + 2 });
  expect((await billing.status('alice')).canRunCloud).toBe(true);
});
it('keeps Mac execution and agent setup available without a subscription', async () => {
  await cloud.settings('alice', { executionTarget: 'computer' });
  const result = await cloud.command('alice', {
    id: randomUUID(),
    executionTarget: 'cloud',
    action: {
      type: 'mode.set',
      mode: 'proactive',
      expectedMode: 'off'
    }
  });
  expect(result.status).toBe('completed');
  await expect(
    cloud.edit('alice', (snapshot) => {
      snapshot.agents[0]!.name = 'My agent';
    })
  ).resolves.toBeUndefined();
});
it('rejects cloud jobs without balance but preserves the task and original snapshot', async () => {
  const before = (await cloud.state('alice', -1, [])).snapshot!;
  const thread = randomUUID();
  await cloud.command('alice', {
    id: randomUUID(),
    executionTarget: 'cloud',
    action: {
      type: 'chat.create',
      threadId: thread,
      agentId: before.agents[0]!.id
    }
  });
  const response = await cloud.command('alice', {
    id: randomUUID(),
    executionTarget: 'cloud',
    action: { type: 'chat.send', threadId: thread, message: 'Hello', files: [] }
  });
  expect(response.status).toBe('failed');
  expect((await db.pool.query('SELECT id FROM cloud_jobs')).rows).toHaveLength(
    0
  );
  expect(
    (await cloud.state('alice', -1, [])).snapshot?.threads.find(
      (value) => value.id === thread
    )?.messages
  ).toHaveLength(0);
});
it('reconciles unknown holds without letting a failed provider call consume allowance', async () => {
  await billing.apply(purchase());
  const job = await cloud.createOnboardingJob('alice');
  const id = await cloud.reserve(job, 2);
  await cloud.markUnknownCost(id);
  expect((await billing.status('alice')).monthlyUsedPercent).toBeCloseTo(
    200 / 7
  );
  await cloud.settle(id, undefined);
  expect((await billing.status('alice')).monthlyUsedPercent).toBeCloseTo(
    200 / 7
  );
  await cloud.settle(id, 0.25);
  await cloud.settle(id, 0);
  expect((await billing.status('alice')).monthlyUsedPercent).toBeCloseTo(
    25 / 7
  );
});

it('uses released monthly holds before consuming non-expiring extras', async () => {
  await billing.apply(purchase());
  await billing.apply(purchase('extra.20', { expiresAt: null }));
  const first = await spend(7_000_000);
  const second = await spend(2_000_000);
  await db.pool.transaction((client) => billing.settle(client, first, 0));
  await db.pool.transaction((client) =>
    billing.settle(client, second, 2_000_000)
  );
  const status = await billing.status('alice');
  expect(status.monthlyUsedPercent).toBeCloseTo(200 / 7);
  expect(status.extraRemainingPercent).toBe(100);
});

it('restricts sandbox grants on a production ledger to explicit test accounts', async () => {
  const production = new BillingStore(
    db.pool,
    true,
    () => now,
    new Set(['reviewer'])
  );
  await expect(
    production.apply(purchase('pro.monthly', { id: 'Sandbox:test' }), 'alice')
  ).rejects.toThrow('test accounts');
  await production.apply(
    purchase('pro.monthly', { id: 'Production:paid' }),
    'alice'
  );
  expect((await production.status('alice')).plan).toBe('pro');
});

it('wakes annual-plan work at the next monthly reset without a purchase notification', async () => {
  await cloud.state('alice', -1, []);
  await billing.apply(purchase('pro.yearly'));
  await billing.refreshPeriods();
  await spend(7_000_000);
  await db.pool.query('DELETE FROM cloud_planning_pending');
  await billing.refreshPeriods();
  expect(
    (await db.pool.query('SELECT * FROM cloud_planning_pending')).rows
  ).toHaveLength(0);

  now = Date.parse('2026-02-28T12:00:00Z');
  await billing.refreshPeriods();
  expect((await billing.status('alice')).monthlyUsedPercent).toBe(0);
  expect(
    (await db.pool.query('SELECT * FROM cloud_planning_pending')).rows
  ).toHaveLength(1);
  expect(
    (
      await db.pool.query<{ next_ms: number }>(
        'SELECT next_ms FROM billing_refresh'
      )
    ).rows[0]?.next_ms
  ).toBe(Date.parse('2026-03-31T12:00:00Z'));

  now = Date.parse('2027-01-31T12:00:00Z');
  await db.pool.query('DELETE FROM cloud_planning_pending');
  await billing.refreshPeriods();
  expect(
    (await db.pool.query('SELECT * FROM billing_refresh')).rows
  ).toHaveLength(0);
  expect(
    (await db.pool.query('SELECT * FROM cloud_planning_pending')).rows
  ).toHaveLength(0);
});

it('keeps deleted-account purchases tombstoned and accepts webhook redelivery harmlessly', async () => {
  const p = purchase();
  await billing.apply(p);
  await db.pool.query(
    'UPDATE billing_accounts SET user_id = NULL WHERE id = $1',
    [token]
  );
  await expect(
    billing.apply({ ...p, signedAt: now + 1 })
  ).resolves.toBeUndefined();
  await expect(billing.apply(p, 'alice')).rejects.toThrow(
    'another Dony account'
  );
  expect((await billing.status('alice')).accountToken).not.toBe(token);
  expect((await billing.status('alice')).canRunCloud).toBe(false);
});

// The retained plus IDs now sell Max; the retired high-price IDs must not grant usage.
it('keeps Max at five times Pro and rejects retired subscriptions', async () => {
  await billing.apply(purchase('plus.monthly'));
  expect((await billing.status('alice')).plan).toBe('plus');
  await spend(35_000_000);
  await expect(spend(1)).rejects.toThrow('used this month');
  for (const period of ['monthly', 'yearly']) {
    await expect(billing.apply(purchase(`max.${period}`))).rejects.toThrow(
      'not a Dony product'
    );
  }
});

it('grants Connect remote access without a cloud allowance and removes it on expiry or refund', async () => {
  const p = purchase('connect.yearly');
  await billing.apply(p, 'alice');
  expect(await billing.status('alice')).toMatchObject({
    plan: 'connect', canUseRemoteDesktop: true, canRunCloud: false,
    limitReached: false, resetsAt: null, monthlyUsedPercent: 0
  });
  await expect(spend(1)).rejects.toMatchObject({ status: 403 });
  now = p.expiresAt!;
  expect((await billing.status('alice')).canUseRemoteDesktop).toBe(false);
  now = p.purchasedAt + 1;
  await billing.apply({ ...p, revokedAt: now, signedAt: now });
  expect((await billing.status('alice')).canUseRemoteDesktop).toBe(false);
});
it('keeps remote access after Pro cloud usage is exhausted, but extras alone do not grant it', async () => {
  await billing.apply(purchase('extra.20', { expiresAt: null }));
  expect(await billing.status('alice')).toMatchObject({ canRunCloud: true, canUseRemoteDesktop: false });
  await billing.apply(purchase());
  await spend(14_000_000);
  expect(await billing.status('alice')).toMatchObject({ canRunCloud: false, canUseRemoteDesktop: true, limitReached: true });
});
