import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import { Webhook } from 'svix';
import { z } from 'zod';
import type { AuthUser } from '@dony/domain';
import { CloudError } from '../cloudCommands';
import type { BillingStore } from './store';
import type { AppleBilling } from './apple';

export function billingRoutes(
  store: BillingStore,
  apple: Pick<AppleBilling, 'transaction' | 'transactionId' | 'notification'>,
  authenticate: (headers: Headers) => Promise<AuthUser | Response>,
  wake: () => void,
  webhookSecret?: string
) {
  const app = new Hono<{ Variables: { user: AuthUser } }>();
  app.use('*', bodyLimit({ maxSize: 256 * 1024 }));
  app.onError((error, c) => {
    if (error instanceof z.ZodError)
      return c.json({ error: 'Invalid billing request.' }, 400);
    if (error instanceof CloudError)
      return c.json({ error: error.message }, error.status);
    console.error(
      'Billing request failed.',
      error instanceof Error ? error.name : 'Error'
    );
    return c.json(
      {
        error:
          'Couldn’t confirm your purchase yet. Your payment will not be charged again when you retry.'
      },
      503
    );
  });
  app.post('/apple', async (c) => {
    const { signedPayload } = z
      .object({ signedPayload: z.string().min(1).max(100_000) })
      .parse(await c.req.json());
    const purchase = await apple.notification(signedPayload);
    if (purchase) await store.apply(purchase);
    wake();
    return c.json({ ok: true });
  });
  app.post('/superwall', async (c) => {
    if (!webhookSecret)
      throw new CloudError(503, 'Billing notifications are not configured.');
    let event: unknown;
    try {
      const payload = await c.req.text();
      new Webhook(webhookSecret).verify(payload, {
        'svix-id': c.req.header('svix-id') ?? '',
        'svix-timestamp': c.req.header('svix-timestamp') ?? '',
        'svix-signature': c.req.header('svix-signature') ?? ''
      });
      event = JSON.parse(payload);
    } catch {
      throw new CloudError(400, 'Invalid billing notification.');
    }
    const parsed = z
      .object({
        data: z.object({
          store: z.string(),
          environment: z.enum(['PRODUCTION', 'SANDBOX']),
          bundleId: z.string().nullish(),
          transactionId: z.string().nullish()
        })
      })
      .parse(event);
    if (
      parsed.data.store === 'APP_STORE' &&
      parsed.data.bundleId === 'com.dony.solari.mobile' &&
      parsed.data.transactionId
    ) {
      await store.apply(
        await apple.transactionId(
          parsed.data.transactionId,
          parsed.data.environment === 'SANDBOX'
        )
      );
      wake();
    }
    return c.json({ ok: true });
  });
  app.use('*', async (c, next) => {
    const user = await authenticate(c.req.raw.headers);
    if (user instanceof Response) return user;
    c.set('user', user);
    await next();
  });
  app.get('/', async (c) => c.json(await store.status(c.get('user').id)));
  app.post('/sync', async (c) => {
    const { transactions } = z
      .object({
        transactions: z.array(z.string().min(1).max(50_000)).min(1).max(10)
      })
      .parse(await c.req.json());
    for (const signed of transactions)
      await store.apply(await apple.transaction(signed), c.get('user').id);
    wake();
    return c.json(await store.status(c.get('user').id));
  });
  return app;
}
