import { randomUUID } from 'node:crypto';

import { serve } from '@hono/node-server';
import { getMigrations } from 'better-auth/db/migration';
import { Hono } from 'hono';

import {
  authDesktopExchangeInputSchema,
  authDesktopStartInputSchema,
  connectorConnectResultSchema,
  connectorFileMaxBytes,
  connectorRefreshResultSchema,
  connectorsStatusSchema,
  authUserSchema,
  nativeAgentLocalToolCallSchema,
  nativeAgentLocalToolResultSchema,
  nativeAgentLocalToolResultInputSchema,
  nativeAgentStreamEventSchema,
  nativeAgentRunRequestSchema,
  type AuthUser
} from '@dony/domain';

import { auth } from './auth';
import { assertNever, config } from './config';
import { composioConnectorService } from './composioConnectorService';
import { initializeDatabase, createDatabase } from './database';
import { CompanionStore } from './companionStore';
import { createCompanionRoutes } from './companionRoutes';
import { localToolResultStore } from './localToolResultStore';
import { modelGateway } from './modelGateway';
import { CloudStore, deleteDonyAccountData } from './cloudStore';
import { AppleBilling } from './billing/apple';
import { BillingStore } from './billing/store';
import { billingRoutes } from './billing/routes';
import { CloudError } from './cloudCommands';
import { createCloudModel } from './cloudModel';
import { CloudWorker } from './cloudWorker';
import { CloudRecovery } from './cloudRecovery';
import { CloudPush } from './cloudPush';
import { createMobileRoutes } from './mobileRoutes';
import { createMobileAuthRoutes, migrateMobileAuth } from './mobileAuth';

const app = new Hono();
const desktopHandoffTtlMs = 5 * 60 * 1000;
const desktopHandoffs = new Map<
  string,
  { token: string; user: AuthUser; expiresAt: number }
>();

const devUser = authUserSchema.parse({
  id: 'dev-user',
  email: 'dev@dony.local',
  name: 'Dony Dev',
  avatarUrl: null
});

const bearerToken = (headers: Headers): string | null => {
  const authorization = headers.get('authorization');

  if (!authorization?.startsWith('Bearer ')) {
    return null;
  }

  return authorization.slice('Bearer '.length).trim() || null;
};

const authenticateRequest = async (
  headers: Headers
): Promise<AuthUser | Response> => {
  const token = bearerToken(headers);

  if (config.auth.type === 'dev') {
    return token === config.auth.token
      ? devUser
      : Response.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const session = await auth.api.getSession({ headers });

  return session
    ? toAuthUser(session)
    : Response.json({ error: 'Unauthorized' }, { status: 401 });
};

const isUnauthorized = (value: AuthUser | Response): value is Response =>
  value instanceof Response;

const createDesktopHandoff = (token: string, user: AuthUser): string => {
  const code = randomUUID();

  desktopHandoffs.set(code, {
    token,
    user,
    expiresAt: Date.now() + desktopHandoffTtlMs
  });

  return code;
};

const consumeDesktopHandoff = (
  code: string
): { token: string; user: AuthUser } | null => {
  const handoff = desktopHandoffs.get(code);
  desktopHandoffs.delete(code);

  if (!handoff || handoff.expiresAt < Date.now()) {
    return null;
  }

  return {
    token: handoff.token,
    user: handoff.user
  };
};

const toAuthUser = (
  session: NonNullable<Awaited<ReturnType<typeof auth.api.getSession>>>
): AuthUser =>
  authUserSchema.parse({
    id: session.user.id,
    email: session.user.email ?? null,
    name: session.user.name ?? null,
    avatarUrl: session.user.image ?? null
  });

const assertDesktopCallbackUrl = (callbackUrl: string): void => {
  const url = new URL(callbackUrl);

  if (url.protocol !== 'dony:' || url.hostname !== 'auth') {
    throw new Error('Expected Dony auth callback URL.');
  }

  if (url.pathname !== '/callback') {
    throw new Error('Expected Dony auth callback path.');
  }
};

const desktopCallbackUrl = (callbackUrl: string, code: string): string => {
  assertDesktopCallbackUrl(callbackUrl);
  const url = new URL(callbackUrl);

  url.searchParams.set('code', code);

  return url.toString();
};

app.get('/health', (context) =>
  context.json({
    ok: true
  })
);

app.on(['GET', 'POST'], '/api/auth/*', (context) =>
  auth.handler(context.req.raw)
);

app.get('/v1/me', async (context) => {
  const token = bearerToken(context.req.raw.headers);

  if (config.auth.type === 'dev' && token === config.auth.token) {
    return context.json({ user: devUser });
  }

  const session = await auth.api.getSession({
    headers: context.req.raw.headers
  });

  if (!session) {
    return context.json({ error: 'Unauthorized' }, 401);
  }

  return context.json({
    user: toAuthUser(session)
  });
});

app.post('/v1/auth/desktop/start', async (context) => {
  const body = authDesktopStartInputSchema.parse(await context.req.json());

  try {
    assertDesktopCallbackUrl(body.callbackUrl);
  } catch {
    return context.json({ error: 'Invalid desktop callback URL.' }, 400);
  }

  switch (config.auth.type) {
    case 'dev': {
      const code = createDesktopHandoff(config.auth.token, devUser);

      return context.json({
        url: desktopCallbackUrl(body.callbackUrl, code)
      });
    }
    case 'google': {
      const url = new URL('/v1/auth/desktop/google', config.baseUrl);

      url.searchParams.set('callbackUrl', body.callbackUrl);

      return context.json({ url: url.toString() });
    }
    default:
      return assertNever(config.auth);
  }
});

app.get('/v1/auth/desktop/google', async (context) => {
  const callbackUrl = context.req.query('callbackUrl');

  if (!callbackUrl) {
    return context.json({ error: 'Desktop callback URL is required.' }, 400);
  }

  try {
    assertDesktopCallbackUrl(callbackUrl);
  } catch {
    return context.json({ error: 'Invalid desktop callback URL.' }, 400);
  }

  const completeUrl = new URL('/v1/auth/desktop/complete', config.baseUrl);
  completeUrl.searchParams.set('callbackUrl', callbackUrl);

  const response = await auth.handler(
    new Request(new URL('/api/auth/sign-in/social', config.baseUrl), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        provider: 'google',
        callbackURL: completeUrl.toString()
      })
    })
  );
  const location = response.headers.get('location');
  const stateCookie = response.headers.get('set-cookie');

  if (!response.ok || !location || !stateCookie) {
    return context.json({ error: 'Unable to start Google sign-in.' }, 502);
  }

  const headers = new Headers(response.headers);
  headers.delete('content-length');
  headers.delete('content-type');

  return new Response(null, { status: 302, headers });
});

app.get('/v1/auth/desktop/complete', async (context) => {
  const callbackUrl = context.req.query('callbackUrl');

  if (!callbackUrl) {
    return context.json({ error: 'Desktop callback URL is required.' }, 400);
  }

  try {
    assertDesktopCallbackUrl(callbackUrl);
  } catch {
    return context.json({ error: 'Invalid desktop callback URL.' }, 400);
  }

  const session = await auth.api.getSession({
    headers: context.req.raw.headers
  });

  if (!session) {
    return context.json({ error: 'Unauthorized' }, 401);
  }

  const code = createDesktopHandoff(session.session.token, toAuthUser(session));

  return context.redirect(desktopCallbackUrl(callbackUrl, code));
});

app.post('/v1/auth/desktop/exchange', async (context) => {
  const body = authDesktopExchangeInputSchema.parse(await context.req.json());
  const handoff = consumeDesktopHandoff(body.code);

  if (!handoff) {
    return context.json(
      { error: 'Desktop callback cannot be exchanged.' },
      400
    );
  }

  return context.json({
    token: handoff.token,
    user: handoff.user
  });
});

app.post('/v1/auth/logout', async (context) => {
  await auth.handler(
    new Request(new URL('/api/auth/sign-out', config.baseUrl), {
      method: 'POST',
      headers: context.req.raw.headers
    })
  );

  return context.json({ ok: true });
});

// The older desktop OpenAI gateway has no provider-cost reconciliation. Once
// billing is configured, only the metered cloud runner may spend Dony funds.
app.use('/v1/native-agent/runs*', async (context, next) => {
  if (appleBilling.configured && config.modelGateway.type === 'openai')
    return context.json({ error: 'Use Dony cloud agents or your Mac’s ChatGPT connection. This older AI connection does not support Dony subscriptions.' }, 503);
  await next();
});

app.post('/v1/native-agent/runs', async (context) => {
  const user = await authenticateRequest(context.req.raw.headers);

  if (isUnauthorized(user)) {
    return user;
  }

  const request = nativeAgentRunRequestSchema.parse(await context.req.json());
  const response = await modelGateway.run(request, context.req.raw.signal);

  return context.json(response);
});

app.post('/v1/native-agent/runs/stream', async (context) => {
  const user = await authenticateRequest(context.req.raw.headers);

  if (isUnauthorized(user)) {
    return user;
  }

  const request = nativeAgentRunRequestSchema.parse(await context.req.json());
  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send = (event: unknown): void => {
        const parsed = nativeAgentStreamEventSchema.parse(event);
        controller.enqueue(
          encoder.encode(`data: ${JSON.stringify(parsed)}\n\n`)
        );
      };

      try {
        for await (const event of modelGateway.runStream(
          request,
          context.req.raw.signal,
          {
            waitForLocalToolResult: (callId) =>
              localToolResultStore.waitFor(
                request.runId ?? request.threadId,
                callId,
                context.req.raw.signal
              )
          }
        )) {
          send(event);
        }
      } catch (error) {
        send({
          type: 'error',
          message:
            error instanceof Error ? error.message : 'Dony model stream failed.'
        });
      } finally {
        controller.close();
      }
    }
  });

  return new Response(stream, {
    headers: {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-cache',
      'x-accel-buffering': 'no'
    }
  });
});

app.post('/v1/native-agent/local-tool-results', async (context) => {
  const user = await authenticateRequest(context.req.raw.headers);

  if (isUnauthorized(user)) {
    return user;
  }

  const body = nativeAgentLocalToolResultInputSchema.parse(
    await context.req.json()
  );

  await localToolResultStore.save(body.runId, body.result);

  return context.json({ ok: true });
});

app.post('/v1/native-agent/connector-files', async (context) => {
  const user = await authenticateRequest(context.req.raw.headers);

  if (isUnauthorized(user)) {
    return user;
  }

  try {
    const formData = await context.req.raw.formData();
    const file = formData.get('file');
    const toolkit = formData.get('toolkit');
    const toolSlug = formData.get('toolSlug');

    if (!(file instanceof File)) {
      throw new Error('Connector file is required.');
    }

    if (typeof toolkit !== 'string' || toolkit.trim().length === 0) {
      throw new Error('Connector toolkit is required.');
    }

    if (typeof toolSlug !== 'string' || toolSlug.trim().length === 0) {
      throw new Error('Connector tool slug is required.');
    }

    if (file.size > connectorFileMaxBytes) {
      throw new Error('Connector uploads cannot exceed 25 MB per action.');
    }

    return context.json(
      await composioConnectorService.stageFile({
        file,
        toolkit,
        toolSlug,
        signal: context.req.raw.signal
      })
    );
  } catch (error) {
    return context.json(
      {
        error:
          error instanceof Error
            ? error.message
            : 'Unable to stage connector file.'
      },
      400
    );
  }
});

app.post('/v1/native-agent/connector-tool', async (context) => {
  const user = await authenticateRequest(context.req.raw.headers);

  if (isUnauthorized(user)) {
    return user;
  }

  const call = nativeAgentLocalToolCallSchema.parse(await context.req.json());

  try {
    const result = await composioConnectorService.execute(
      user.id,
      call.arguments,
      context.req.raw.signal
    );

    return context.json(
      nativeAgentLocalToolResultSchema.parse({
        callId: call.id,
        status: 'success',
        content: JSON.stringify(result, null, 2)
      })
    );
  } catch (error) {
    return context.json(
      nativeAgentLocalToolResultSchema.parse({
        callId: call.id,
        status: 'error',
        content:
          error instanceof Error
            ? error.message
            : 'Unable to execute connector tool.'
      })
    );
  }
});

app.get('/v1/connectors', async (context) => {
  const user = await authenticateRequest(context.req.raw.headers);

  if (isUnauthorized(user)) {
    return user;
  }

  return context.json(
    connectorsStatusSchema.parse(await composioConnectorService.list(user.id))
  );
});

app.post('/v1/connectors/:toolkit/connect', async (context) => {
  const user = await authenticateRequest(context.req.raw.headers);

  if (isUnauthorized(user)) {
    return user;
  }

  let url: string;

  try {
    url = await composioConnectorService.connect(
      user.id,
      context.req.param('toolkit')
    );
  } catch (error) {
    return context.json(
      {
        error:
          error instanceof Error
            ? error.message
            : 'Unable to start connector authorization.'
      },
      400
    );
  }

  return context.json(connectorConnectResultSchema.parse({ url }));
});

app.post(
  '/v1/connectors/accounts/:connectedAccountId/refresh',
  async (context) => {
    const user = await authenticateRequest(context.req.raw.headers);

    if (isUnauthorized(user)) {
      return user;
    }

    try {
      const url = await composioConnectorService.refresh(
        user.id,
        context.req.param('connectedAccountId')
      );

      return context.json(connectorRefreshResultSchema.parse({ url }));
    } catch (error) {
      return context.json(
        {
          error:
            error instanceof Error
              ? error.message
              : 'Unable to refresh the connected account.'
        },
        400
      );
    }
  }
);

app.post(
  '/v1/connectors/accounts/:connectedAccountId/enable',
  async (context) => {
    const user = await authenticateRequest(context.req.raw.headers);

    if (isUnauthorized(user)) {
      return user;
    }

    try {
      await composioConnectorService.setEnabled(
        user.id,
        context.req.param('connectedAccountId'),
        true
      );

      return context.json({ success: true });
    } catch (error) {
      return context.json(
        {
          error:
            error instanceof Error
              ? error.message
              : 'Unable to resume the connected account.'
        },
        400
      );
    }
  }
);

app.post(
  '/v1/connectors/accounts/:connectedAccountId/disable',
  async (context) => {
    const user = await authenticateRequest(context.req.raw.headers);

    if (isUnauthorized(user)) {
      return user;
    }

    try {
      await composioConnectorService.setEnabled(
        user.id,
        context.req.param('connectedAccountId'),
        false
      );

      return context.json({ success: true });
    } catch (error) {
      return context.json(
        {
          error:
            error instanceof Error
              ? error.message
              : 'Unable to pause the connected account.'
        },
        400
      );
    }
  }
);

app.delete('/v1/connectors/accounts/:connectedAccountId', async (context) => {
  const user = await authenticateRequest(context.req.raw.headers);

  if (isUnauthorized(user)) {
    return user;
  }

  try {
    await composioConnectorService.disconnect(
      user.id,
      context.req.param('connectedAccountId')
    );

    return context.json({ success: true });
  } catch (error) {
    return context.json(
      {
        error:
          error instanceof Error
            ? error.message
            : 'Unable to disconnect the account.'
      },
      400
    );
  }
});

const cloudPool = createDatabase(config.d1);
const appleBilling = new AppleBilling();
const billingStore = new BillingStore(cloudPool, appleBilling.configured, Date.now,
  process.env.DONY_APP_STORE_ENVIRONMENT === 'Sandbox' ? null :
    new Set((process.env.DONY_BILLING_SANDBOX_USER_IDS ?? '').split(',').map(id => id.trim()).filter(Boolean)));
const companionStore = new CompanionStore(createDatabase(config.d1), billingStore);
app.route('/v1/companion', createCompanionRoutes(companionStore, authenticateRequest));
const cloudStore = new CloudStore(cloudPool, billingStore);
const cloudModel = createCloudModel(cloudStore, {
  ...(process.env.DONY_OPENROUTER_API_KEY ? { apiKey: process.env.DONY_OPENROUTER_API_KEY } : {}),
  ...(process.env.DONY_CLOUD_MODEL ? { model: process.env.DONY_CLOUD_MODEL } : {})
});
const cloudWorker = new CloudWorker(cloudStore, cloudModel, composioConnectorService);
app.route('/v1/billing', billingRoutes(billingStore, appleBilling, authenticateRequest,
  () => cloudWorker.wake(), process.env.DONY_SUPERWALL_WEBHOOK_SECRET));
const cloudPush = new CloudPush(cloudPool, process.env.DONY_APNS_KEY_ID && process.env.DONY_APNS_TEAM_ID && process.env.DONY_APNS_PRIVATE_KEY && process.env.DONY_APNS_TOPIC ? {
  keyId: process.env.DONY_APNS_KEY_ID, teamId: process.env.DONY_APNS_TEAM_ID,
  privateKey: process.env.DONY_APNS_PRIVATE_KEY.replace(/\\n/g, '\n'), topic: process.env.DONY_APNS_TOPIC
} : null);
app.route('/v1/mobile/auth', createMobileAuthRoutes(cloudPool, auth, config.baseUrl,
  config.auth.type === 'dev' ? { token: config.auth.token, user: devUser } : undefined));
app.route('/v1/mobile', createMobileRoutes(
  cloudStore,
  authenticateRequest,
  cloudModel.configured,
  composioConnectorService,
  cloudModel,
  async (headers) => {
    if (config.auth.type === 'dev') {
      await composioConnectorService.disconnectAll(devUser.id);
      await deleteDonyAccountData(cloudPool, devUser.id);
      return;
    }
    const response = await auth.handler(
      new Request(new URL('/api/auth/delete-user', config.baseUrl), {
        method: 'POST',
        headers,
        body: '{}'
      })
    );
    if (response.ok) return;

    const result = (await response.json().catch(() => ({}))) as {
      code?: string;
      message?: string;
    };
    throw new CloudError(
      response.status === 401 ? 401 : 400,
      result.code === 'SESSION_EXPIRED'
        ? 'Sign out, sign back in, and try deleting your account again.'
        : result.message ?? 'Could not delete your Dony account.'
    );
  }
));

const migrateAuthDatabase = async (): Promise<void> => {
  const { runMigrations } = await getMigrations(auth.options);
  await runMigrations();
};

await initializeDatabase({
  allowUnavailable: config.auth.type === 'dev',
  migrateAuth: migrateAuthDatabase,
  migrateLocalToolResults: async () => {
    await localToolResultStore.migrate();
    await companionStore.migrate();
    await cloudStore.migrate();
    await billingStore.migrate();
    await migrateMobileAuth(cloudPool);
  },
  cleanupLocalToolResults: () => localToolResultStore.cleanupExpired()
});

cloudStore.onWorkAvailable = () => cloudWorker.wake();
cloudStore.onNotificationsAvailable = () => cloudPush.wake();
const cloudRecovery = new CloudRecovery(cloudPool, () => {
  cloudWorker.wake();
  cloudPush.wake();
});
cloudWorker.start();
cloudPush.start();
cloudRecovery.start();
process.once('SIGTERM', () => { cloudRecovery.stop(); cloudWorker.stop(); cloudPush.stop(); });

serve(
  {
    fetch: app.fetch,
    hostname: '0.0.0.0',
    port: config.port
  },
  (info) => {
    console.log(`Dony API listening on 0.0.0.0:${info.port}`);
  }
);

export { app };
