import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import { z } from 'zod';
import {
  companionCommandSchema,
  companionExchangeSchema,
  type AuthUser
} from '@dony/domain';
import { CompanionError, type CompanionStore } from './companionStore';

export const createCompanionRoutes = (
  store: CompanionStore,
  authenticate: (headers: Headers) => Promise<AuthUser | Response>
): Hono => {
  const app = new Hono();
  app.use(
    '*',
    bodyLimit({
      maxSize: 32 * 1024 * 1024,
      onError: (c) =>
        c.json(
          { error: 'This request exceeds the mobile transfer limit.' },
          413
        )
    })
  );
  app.onError((error, context) => {
    if (error instanceof z.ZodError)
      return context.json(
        { error: 'Invalid companion request.', details: error.flatten() },
        400
      );
    if (error instanceof CompanionError)
      return context.json({ error: error.message }, error.status);
    console.error('Companion request failed', error);
    return context.json(
      {
        error:
          'The desktop connection is temporarily unavailable. Your changes will retry.'
      },
      503
    );
  });
  const owner = async (headers: Headers): Promise<AuthUser> => {
    const user = await authenticate(headers);
    if (user instanceof Response)
      throw new CompanionError(401, 'Sign in to Dony on your desktop first.');
    return user;
  };
  const phone = (headers: Headers) =>
    store.device(headers.get('authorization')?.replace(/^Bearer /, '') ?? '');
  const desktopId = (value: string) => z.string().uuid().parse(value);

  app.post('/desktops', async (c) => {
    const user = await owner(c.req.raw.headers);
    const input = z
      .object({
        id: z.string().uuid(),
        name: z.string().trim().min(1).max(100)
      })
      .parse(await c.req.json());
    await store.register(user.id, input.id, input.name);
    return c.json({ ok: true });
  });
  app.put('/desktops/:id/devices', async (c) => {
    const user = await owner(c.req.raw.headers);
    const body = z.object({ devices: z.array(z.object({
      id: z.string().uuid(), name: z.string().trim().min(1).max(100),
      tokenHash: z.string().regex(/^[a-f0-9]{64}$/)
    })).max(100) }).parse(await c.req.json());
    await store.syncDevices(user.id, desktopId(c.req.param('id')), body.devices);
    return c.json({ ok: true });
  });
  app.post('/desktops/:id/pairings', async (c) => {
    const user = await owner(c.req.raw.headers);
    await store.requireRemoteAccess(user.id);
    return c.json(await store.pairCode(user.id, desktopId(c.req.param('id'))));
  });
  app.get('/desktops/:id/devices', async (c) => {
    const user = await owner(c.req.raw.headers);
    return c.json({
      devices: await store.devices(user.id, desktopId(c.req.param('id')))
    });
  });
  app.delete('/desktops/:id/devices/:deviceId', async (c) => {
    const user = await owner(c.req.raw.headers);
    await store.revoke(
      user.id,
      desktopId(c.req.param('id')),
      desktopId(c.req.param('deviceId'))
    );
    return c.json({ ok: true });
  });
  app.delete('/desktops/:id', async (c) => {
    const user = await owner(c.req.raw.headers);
    await store.disconnect(user.id, desktopId(c.req.param('id')));
    return c.json({ ok: true });
  });
  app.post('/desktops/:id/exchange', async (c) => {
    const user = await owner(c.req.raw.headers);
    const body = companionExchangeSchema.parse(await c.req.json());
    return c.json({
      commands: await store.exchange(
        user.id,
        desktopId(c.req.param('id')),
        body.snapshot,
        body.receipts
      )
    });
  });
  app.post('/pair', async (c) => {
    const body = z
      .object({
        code: z.string().min(24).max(64),
        name: z.string().trim().min(1).max(100)
      })
      .parse(await c.req.json());
    return c.json(await store.pair(body.code, body.name));
  });
  app.post('/state', async (c) => {
    const device = await phone(c.req.raw.headers);
    const body = z
      .object({
        revision: z.number().int().min(-1),
        commandIds: z.string().uuid().array().max(100)
      })
      .parse(await c.req.json());
    return c.json(await store.state(device, body.revision, body.commandIds));
  });
  app.post('/commands', async (c) => {
    const device = await phone(c.req.raw.headers);
    await store.submit(
      device,
      companionCommandSchema.parse(await c.req.json())
    );
    return c.json({ ok: true });
  });
  app.delete('/device', async (c) => {
    const device = await phone(c.req.raw.headers);
    await store.revokeDevice(device.desktop_id, device.id);
    return c.json({ ok: true });
  });
  return app;
};
