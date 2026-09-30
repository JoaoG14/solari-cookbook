import { generateKeyPairSync } from 'node:crypto';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { Webhook } from 'svix';
import { companionTestDatabase } from './helpers/companionDatabase';
import { CloudStore } from '../src/cloudStore';
import { BillingStore, type VerifiedPurchase } from '../src/billing/store';
import { AppleBilling } from '../src/billing/apple';
import { billingRoutes } from '../src/billing/routes';
import { CloudError } from '../src/cloudCommands';

let db: Awaited<ReturnType<typeof companionTestDatabase>>;
let store: BillingStore;
let purchase: VerifiedPurchase;
const secret = 'whsec_' + Buffer.alloc(32, 1).toString('base64');
const authenticate = async (headers: Headers) =>
  headers.get('authorization') === 'Bearer alice'
    ? { id: 'alice', name: null, email: null, avatarUrl: null }
    : new Response('Unauthorized', { status: 401 });
const apple = {
  transaction: vi.fn(),
  transactionId: vi.fn(),
  notification: vi.fn()
};
beforeEach(async () => {
  vi.resetAllMocks();
  db = await companionTestDatabase();
  await new CloudStore(db.pool).migrate();
  store = new BillingStore(db.pool, true);
  await store.migrate();
  purchase = {
    id: 'Sandbox:1',
    originalId: 'Sandbox:1',
    accountToken: await store.account('alice'),
    productId: 'com.dony.solari.mobile.extra.20',
    purchasedAt: Date.now(),
    signedAt: Date.now(),
    expiresAt: null,
    revokedAt: null,
    upgraded: false
  };
  apple.transaction.mockResolvedValue(purchase);
  apple.transactionId.mockResolvedValue(purchase);
});
afterEach(async () => {
  await db.database.close();
});
it('requires authentication for balances and syncing purchases', async () => {
  const app = billingRoutes(store, apple, authenticate, () => {});
  expect((await app.request('/')).status).toBe(401);
  expect((await app.request('/sync', { method: 'POST' })).status).toBe(401);
  expect(apple.transaction).not.toHaveBeenCalled();
});
it('grants a verified consumable exactly once across repeat syncs', async () => {
  const app = billingRoutes(store, apple, authenticate, () => {});
  const request = {
    method: 'POST',
    headers: {
      authorization: 'Bearer alice',
      'content-type': 'application/json'
    },
    body: JSON.stringify({ transactions: ['verified-fixture'] })
  };
  expect((await app.request('/sync', request)).status).toBe(200);
  const response = await app.request('/sync', request);
  expect(await response.json()).toMatchObject({ extraRemainingPercent: 100 });
});
it('does not accept a client-supplied plan instead of a signed transaction', async () => {
  const app = billingRoutes(store, apple, authenticate, () => {});
  const result = await app.request('/sync', {
    method: 'POST',
    headers: {
      authorization: 'Bearer alice',
      'content-type': 'application/json'
    },
    body: JSON.stringify({ plan: 'max', amount: 70 })
  });
  expect(result.status).toBe(400);
  expect(apple.transaction).not.toHaveBeenCalled();
});
it('rejects forged Apple notifications before changing the balance', async () => {
  apple.notification.mockRejectedValue(
    new CloudError(400, 'Invalid App Store notification.')
  );
  const app = billingRoutes(store, apple, authenticate, () => {});
  expect(
    (
      await app.request('/apple', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ signedPayload: 'forged' })
      })
    ).status
  ).toBe(400);
  expect((await store.status('alice')).canRunCloud).toBe(false);
});
it('checks the Superwall signature and then retrieves the verified Apple transaction', async () => {
  const app = billingRoutes(store, apple, authenticate, () => {}, secret);
  const body = JSON.stringify({
    data: {
      store: 'APP_STORE',
      environment: 'SANDBOX',
      bundleId: 'com.dony.solari.mobile',
      transactionId: '1'
    }
  });
  const date = new Date();
  const headers = {
    'svix-id': 'event-1',
    'svix-timestamp': String(Math.floor(date.getTime() / 1000)),
    'svix-signature': new Webhook(secret).sign('event-1', date, body)
  };
  expect(
    (await app.request('/superwall', { method: 'POST', body, headers })).status
  ).toBe(200);
  expect(apple.transactionId).toHaveBeenCalledWith('1', true);
  expect((await store.status('alice')).extraRemainingPercent).toBe(100);
  expect(
    (
      await app.request('/superwall', {
        method: 'POST',
        body: body + ' ',
        headers
      })
    ).status
  ).toBe(400);
});
it('the real Apple verifier rejects an unsigned client transaction and local StoreKit data', async () => {
  const { privateKey } = generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    publicKeyEncoding: { type: 'spki', format: 'pem' }
  });
  const verifier = new AppleBilling({
    DONY_APP_STORE_ENVIRONMENT: 'Sandbox',
    DONY_APP_STORE_PRIVATE_KEY: privateKey,
    DONY_APP_STORE_KEY_ID: 'key',
    DONY_APP_STORE_ISSUER_ID: 'issuer'
  });
  await expect(verifier.transaction('e30.e30.unsigned')).rejects.toThrow(
    'could not be verified'
  );
  await expect(verifier.notification('e30.e30.unsigned')).rejects.toThrow(
    'Invalid App Store'
  );
});
