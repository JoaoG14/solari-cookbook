import { createHash, randomBytes } from 'node:crypto';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { createMobileAuthRoutes, migrateMobileAuth } from '../src/mobileAuth';
import type { auth } from '../src/auth';
import { companionTestDatabase } from './helpers/companionDatabase';
let database: Awaited<ReturnType<typeof companionTestDatabase>>;
beforeEach(async () => {
  database = await companionTestDatabase();
  await migrateMobileAuth(database.pool);
});
afterEach(async () => {
  await database.database.close();
});
it('requires the initiating phone PKCE secret and consumes the code once', async () => {
  const app = createMobileAuthRoutes(
    database.pool,
    {} as typeof auth,
    'https://dony.test',
    {
      token: 'session',
      user: { id: 'alice', name: null, email: null, avatarUrl: null }
    }
  );
  const verifier = randomBytes(32).toString('base64url');
  const state = randomBytes(32).toString('base64url');
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  const post = (endpoint: string, input: unknown) =>
    app.request(endpoint, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(input)
    });
  const start = (await (await post('/start', { challenge, state })).json()) as {
    url: string;
  };
  const redirect = await app.request(
    start.url.replace('https://dony.test/v1/mobile/auth', '')
  );
  const url = new URL(redirect.headers.get('location')!);
  expect(url.origin).not.toContain('session');
  const code = url.searchParams.get('code');
  expect(
    (
      await post('/exchange', {
        code,
        verifier: randomBytes(32).toString('base64url'),
        state
      })
    ).status
  ).toBe(401);
  expect(
    (await post('/exchange', { code, verifier, state: 'incorrect' })).status
  ).toBe(401);
  const response = await post('/exchange', { code, verifier, state });
  expect(await response.json()).toMatchObject({
    token: 'session',
    user: { id: 'alice' }
  });
  expect((await post('/exchange', { code, verifier, state })).status).toBe(401);
});

it('exchanges a native Apple identity token for a Dony session', async () => {
  const handler = vi.fn(async (request: Request) => {
    expect(await request.json()).toEqual({
      provider: 'apple',
      idToken: {
        token: 'apple-identity-token',
        nonce: 'n'.repeat(43),
        user: {
          name: { firstName: 'Ada', lastName: 'Lovelace' },
          email: 'ada@privaterelay.appleid.com'
        }
      }
    });
    return Response.json({
      token: 'dony-session',
      user: {
        id: 'alice',
        name: 'Ada Lovelace',
        email: 'ada@privaterelay.appleid.com',
        image: null
      }
    });
  });
  const app = createMobileAuthRoutes(
    database.pool,
    { handler } as unknown as typeof auth,
    'https://dony.test'
  );
  const response = await app.request('/apple', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      identityToken: 'apple-identity-token',
      nonce: 'n'.repeat(43),
      user: {
        name: { firstName: 'Ada', lastName: 'Lovelace' },
        email: 'ada@privaterelay.appleid.com'
      }
    })
  });

  expect(response.status).toBe(200);
  expect(await response.json()).toEqual({
    token: 'dony-session',
    user: {
      id: 'alice',
      name: 'Ada Lovelace',
      email: 'ada@privaterelay.appleid.com',
      avatarUrl: null
    }
  });
  expect(handler).toHaveBeenCalledOnce();
});
