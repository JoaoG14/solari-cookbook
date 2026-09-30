import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { Hono } from 'hono';
import { z } from 'zod';
import type { DonyDatabase } from './database';
import type { auth } from './auth';
import type { AuthUser } from '@dony/domain';

const digest = (value: string) =>
  createHash('sha256').update(value).digest('base64url');
export async function migrateMobileAuth(pool: DonyDatabase) {
  await pool.query(`CREATE TABLE IF NOT EXISTS mobile_auth_handoffs (
    id TEXT PRIMARY KEY, challenge TEXT NOT NULL, state TEXT NOT NULL,
    code_hash TEXT, token TEXT, user_data TEXT, expires_at TEXT NOT NULL
  )`);
  await pool.trackTables(['mobile_auth_handoffs']);
}
export function createMobileAuthRoutes(
  pool: DonyDatabase,
  authentication: typeof auth,
  baseUrl: string,
  dev?: { token: string; user: AuthUser }
) {
  const app = new Hono();
  app.use('*', async (context, next) => {
    context.header('Cache-Control', 'no-store');
    await next();
  });
  app.onError((error, c) =>
    c.json(
      {
        error:
          error instanceof z.ZodError
            ? 'Invalid sign-in request.'
            : 'Could not complete Dony sign-in.'
      },
      400
    )
  );
  app.post('/start', async (c) => {
    const input = z
      .object({
        challenge: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
        state: z.string().regex(/^[A-Za-z0-9_-]{32,128}$/)
      })
      .parse(await c.req.json());
    const id = randomBytes(32).toString('base64url');
    await pool.query(
      `DELETE FROM mobile_auth_handoffs WHERE expires_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`,
      []
    );
    await pool.query(
      "INSERT INTO mobile_auth_handoffs(id, challenge, state, expires_at) VALUES ($1,$2,$3,strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+5 minutes'))",
      [id, input.challenge, input.state]
    );
    return c.json({ url: `${baseUrl}/v1/mobile/auth/google?id=${id}` });
  });
  const complete = async (id: string, token: string, user: AuthUser) => {
    const code = randomBytes(32).toString('base64url');
    const result = await pool.query<{ state: string }>(
      `UPDATE mobile_auth_handoffs SET code_hash = $2, token = $3, user_data = $4 WHERE id = $1 AND expires_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now') AND code_hash IS NULL RETURNING state`,
      [id, digest(code), token, JSON.stringify(user)]
    );
    if (!result.rows[0]) throw new Error('Expired sign-in.');
    return `dony-solari-mobile://auth/callback?code=${code}&state=${result.rows[0].state}`;
  };
  app.post('/apple', async (c) => {
    const input = z
      .object({
        identityToken: z.string().min(1).max(16_384),
        nonce: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
        user: z
          .object({
            name: z
              .object({
                firstName: z.string().max(200).optional(),
                lastName: z.string().max(200).optional()
              })
              .optional(),
            email: z.string().email().optional()
          })
          .optional()
      })
      .parse(await c.req.json());
    if (dev) return c.json({ token: dev.token, user: dev.user });
    const response = await authentication.handler(
      new Request(new URL('/api/auth/sign-in/social', baseUrl), {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          provider: 'apple',
          idToken: {
            token: input.identityToken,
            nonce: input.nonce,
            user: input.user
          }
        })
      })
    );
    if (!response.ok) {
      return c.json({ error: 'Could not complete Apple sign-in.' }, 401);
    }
    const result = z
      .object({
        token: z.string(),
        user: z.object({
          id: z.string(),
          name: z.string().nullable().optional(),
          email: z.string().nullable().optional(),
          image: z.string().nullable().optional()
        })
      })
      .parse(await response.json());
    return c.json({
      token: result.token,
      user: {
        id: result.user.id,
        name: result.user.name ?? null,
        email: result.user.email ?? null,
        avatarUrl: result.user.image ?? null
      }
    });
  });
  app.get('/google', async (c) => {
    const id = z
      .string()
      .regex(/^[A-Za-z0-9_-]{43}$/)
      .parse(c.req.query('id'));
    const pending = await pool.query(
      `SELECT id FROM mobile_auth_handoffs WHERE id = $1 AND expires_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now') AND code_hash IS NULL`,
      [id]
    );
    if (!pending.rows.length)
      return c.json(
        { error: 'This sign-in expired. Start again in Dony.' },
        400
      );
    if (dev) return c.redirect(await complete(id, dev.token, dev.user));
    const response = await authentication.handler(
      new Request(new URL('/api/auth/sign-in/social', baseUrl), {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          provider: 'google',
          callbackURL: `${baseUrl}/v1/mobile/auth/complete?id=${id}`
        })
      })
    );
    if (!response.ok || !response.headers.get('location'))
      return c.json({ error: 'Could not start Google sign-in.' }, 503);
    const headers = new Headers(response.headers);
    headers.delete('content-length');
    headers.delete('content-type');
    return new Response(null, { status: 302, headers });
  });
  app.get('/complete', async (c) => {
    const session = await authentication.api.getSession({
      headers: c.req.raw.headers
    });
    if (!session) return c.json({ error: 'Sign in to Dony first.' }, 401);
    const id = z
      .string()
      .regex(/^[A-Za-z0-9_-]{43}$/)
      .parse(c.req.query('id'));
    return c.redirect(
      await complete(id, session.session.token, {
        id: session.user.id,
        name: session.user.name,
        email: session.user.email,
        avatarUrl: session.user.image ?? null
      })
    );
  });
  app.post('/exchange', async (c) => {
    const input = z
      .object({
        code: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
        verifier: z.string().regex(/^[A-Za-z0-9_-]{43,128}$/),
        state: z.string()
      })
      .parse(await c.req.json());
    return pool.transaction(async (client) => {
      const { rows } = await client.query<{
        id: string;
        challenge: string;
        state: string;
        token: string;
        user_data: AuthUser;
      }>(
        `SELECT * FROM mobile_auth_handoffs WHERE code_hash = $1 AND expires_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`,
        [digest(input.code)]
      );
      const handoff = rows[0];
      const challenge = digest(input.verifier);
      if (
        !handoff ||
        handoff.state !== input.state ||
        !timingSafeEqual(Buffer.from(handoff.challenge), Buffer.from(challenge))
      ) {
        return c.json({ error: 'This sign-in is invalid or expired.' }, 401);
      }
      await client.query('DELETE FROM mobile_auth_handoffs WHERE id = $1', [
        handoff.id
      ]);
      return c.json({ token: handoff.token, user: handoff.user_data });
    });
  });
  return app;
}
