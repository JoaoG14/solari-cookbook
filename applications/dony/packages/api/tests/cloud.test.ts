import { randomUUID } from 'node:crypto';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { agentQuestionSchema, mergeCloudSnapshot, type CloudCommand } from '@dony/domain';
import { companionTestDatabase } from './helpers/companionDatabase';
import { CloudStore, deleteDonyAccountData } from '../src/cloudStore';
import { CloudError } from '../src/cloudCommands';
import { CompanionStore } from '../src/companionStore';
import { migrateMobileAuth } from '../src/mobileAuth';
import { CloudWorker } from '../src/cloudWorker';
import { createMobileRoutes } from '../src/mobileRoutes';
import type { BillingStore } from '../src/billing/store';
import type { CloudModel } from '../src/cloudModel';
import type { composioConnectorService } from '../src/composioConnectorService';

let database: Awaited<ReturnType<typeof companionTestDatabase>>;
let store: CloudStore;
const command = (action: CloudCommand['action']): CloudCommand => ({
  id: randomUUID(),
  executionTarget: 'cloud',
  action
});
const state = async (user = 'alice') =>
  (await store.state(user, -1, [])).snapshot!;
async function chat() {
  const snapshot = await state();
  const threadId = randomUUID();
  await store.command(
    'alice',
    command({ type: 'chat.create', threadId, agentId: snapshot.agents[0]!.id })
  );
  return threadId;
}
beforeEach(async () => {
  database = await companionTestDatabase();
  store = new CloudStore(database.pool);
  await store.migrate();
});
afterEach(async () => {
  await database.database.close();
});

describe('cloud access and shared data', () => {
  it('deletes only the requested account and all of its Dony data', async () => {
    await new CompanionStore(database.pool).migrate();
    await migrateMobileAuth(database.pool);
    await store.settings('alice', { pro: true });
    await store.settings('bob', { pro: true });
    const alice = await store.workspace(store.pool, 'alice');
    const bob = await store.workspace(store.pool, 'bob');
    const jobId = randomUUID();
    await store.pool.query(
      "INSERT INTO cloud_jobs(id, workspace_id, thread_id, assistant_message_id, kind, state) VALUES ($1,$2,$3,$4,'chat','completed')",
      [jobId, alice.id, randomUUID(), randomUUID()]);
    await store.pool.query("INSERT INTO cloud_tool_calls(job_id, id, state) VALUES ($1,'tool','completed')", [jobId]);
    await store.pool.query('INSERT INTO cloud_spend(id, job_id, reserved_micros) VALUES ($1,$2,1)', [randomUUID(), jobId]);
    await store.pool.query('INSERT INTO companion_desktops(id, user_id, name) VALUES ($1,$2,$3)', [randomUUID(), 'alice', 'Mac']);
    await store.pool.query(
      "INSERT INTO mobile_auth_handoffs(id, challenge, state, user_data, expires_at) VALUES ('alice-handoff','challenge','state',$1,strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+5 minutes'))",
      [JSON.stringify({ id: 'alice' })]);

    await deleteDonyAccountData(store.pool, 'alice');

    expect((await store.pool.query('SELECT id FROM cloud_workspaces WHERE user_id = $1', ['alice'])).rows).toEqual([]);
    expect((await store.pool.query('SELECT id FROM cloud_workspaces WHERE user_id = $1', ['bob'])).rows).toEqual([{ id: bob.id }]);
    expect((await store.pool.query('SELECT id FROM cloud_jobs WHERE id = $1', [jobId])).rows).toEqual([]);
    expect((await store.pool.query('SELECT id FROM companion_desktops WHERE user_id = $1', ['alice'])).rows).toEqual([]);
    expect((await store.pool.query("SELECT id FROM mobile_auth_handoffs WHERE id = 'alice-handoff'")).rows).toEqual([]);
  });

  it('calls account deletion with the signed-in headers', async () => {
    const remove = vi.fn().mockResolvedValue(undefined);
    const routes = createMobileRoutes(store,
      async () => ({ id: 'alice', name: null, email: null, avatarUrl: null }), true,
      {} as typeof composioConnectorService, undefined, remove);
    const response = await routes.request('/account', {
      method: 'DELETE', headers: { authorization: 'Bearer alice' }
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });
    expect(remove).toHaveBeenCalledWith(expect.any(Headers));
  });

  it('organizes spoken tasks only for Pro or Max and leaves saving to the phone', async () => {
    const status = vi.fn().mockResolvedValue({ plan: 'connect', canRunCloud: true });
    const billing = { status, read: vi.fn().mockResolvedValue({ active: {}, extraRemaining: 0 }) };
    const paidStore = new CloudStore(database.pool, billing as unknown as BillingStore);
    const model = { configured: true, step: vi.fn().mockResolvedValue({
      text: '{"tasks":["Call the dentist","Buy groceries"]}'
    }) };
    const routes = createMobileRoutes(paidStore,
      async () => ({ id: 'alice', name: null, email: null, avatarUrl: null }), true,
      {} as typeof composioConnectorService, model as unknown as CloudModel);
    const request = () => routes.request('/tasks/organize', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ transcript: 'Uh buy groceries and call the dentist' })
    });

    expect((await request()).status).toBe(403);
    expect(model.step).not.toHaveBeenCalled();
    status.mockResolvedValueOnce({ plan: 'pro', canRunCloud: true });
    const response = await request();
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ tasks: ['Call the dentist', 'Buy groceries'] });
    expect(model.step).toHaveBeenCalledTimes(1);
    expect((await state()).tasks).toEqual([]);
  });

  it.each(['gmail', 'outlook'] as const)('allows %s onboarding before Pro with phone authorization URLs and read-only source tasks', async (toolkit) => {
    const connectors = {
      list: vi.fn().mockResolvedValue({ enabled: true, disabledReason: null, toolkits: [
        { slug: toolkit, name: toolkit, isConnected: true, status: 'ACTIVE', connectedAccountId: 'gmail-alice' }
      ] }),
      connect: vi.fn().mockResolvedValue('https://connect.example/email'),
      execute: vi.fn().mockResolvedValue({ successful: true, data: { messages: [
        { id: 'email-1', subject: 'Project update', text: 'Please prepare the update for Friday.' }
      ] } })
    };
    const model = { configured: true, step: vi.fn().mockResolvedValue({ text: JSON.stringify({ suggestions: [
      { messageId: 'email-1', title: 'Draft the project update' }
    ] }) }) };
    const routes = createMobileRoutes(store,
      async () => ({ id: 'alice', name: null, email: null, avatarUrl: null }), true,
      connectors as unknown as typeof composioConnectorService,
      model as unknown as Parameters<typeof createMobileRoutes>[4]);
    const request = (body: unknown) => routes.request('/connectors', {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body)
    });
    expect((await request({ action: 'list' })).status).toBe(200);
    expect(await (await request({ action: 'connect', toolkit })).json())
      .toEqual({ url: 'https://connect.example/email' });
    expect(connectors.connect).toHaveBeenCalledWith('alice', toolkit);
    expect((await request({ action: 'connect', toolkit: 'notion' })).status).toBe(403);
    expect((await request({ action: 'disconnect', connectedAccountId: 'other-account' })).status).toBe(403);
    const otherToolkit = toolkit === 'gmail' ? 'outlook' : 'gmail';
    expect(await (await request({ action: 'suggestEmailTasks', toolkit: otherToolkit })).json()).toEqual({ suggestions: [] });
    expect(connectors.execute).not.toHaveBeenCalled();
    const response = await request({ action: 'suggestEmailTasks', toolkit });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ suggestions: [{ title: 'Draft the project update', subject: 'Project update' }] });
    expect(connectors.execute).toHaveBeenCalledWith('alice', expect.objectContaining({ toolSlug: toolkit === 'outlook' ? 'OUTLOOK_OUTLOOK_LIST_MESSAGES' : 'GMAIL_FETCH_EMAILS' }), expect.any(AbortSignal));
    expect((await state()).tasks).toEqual([]);
    connectors.list.mockResolvedValueOnce({ enabled: true, toolkits: [] });
    expect(await (await request({ action: 'suggestEmailTasks', toolkit })).json()).toEqual({ suggestions: [] });
    expect(model.step).toHaveBeenCalledTimes(1);
    const job = model.step.mock.calls[0]![0];
    expect(job).toMatchObject({ user_id: 'alice', kind: 'onboarding' });
    expect((await store.pool.query('SELECT state FROM cloud_jobs WHERE id = $1', [job.id])).rows[0].state).toBe('completed');
    // These pre-Pro reads reserve and settle against the same cloud usage budget.
    const reservation = await store.reserve(job, 0.001);
    await store.settle(reservation, 0.0005);
  });

  it.each(['chat.archive', 'task.delete'] as const)('%s clears questions and cancels the entire task subtree', async (action) => {
    await store.settings('alice', { pro: true });
    const taskId = randomUUID();
    const childId = randomUUID();
    const unrelatedId = randomUUID();
    for (const [id, parentTaskId] of [
      [taskId, null],
      [childId, taskId],
      [unrelatedId, null]
    ] as const) {
      await store.command(
        'alice',
        command({
          type: 'task.create',
          taskId: id,
          input: { title: id, parentTaskId }
        })
      );
    }
    for (const id of [taskId, childId]) {
      const task = (await state()).tasks.find((item) => item.id === id)!;
      await store.command(
        'alice',
        command({
          type: 'task.suggestion',
          taskId: id,
          expectedUpdatedAt: task.updatedAt,
          action: 'accept'
        })
      );
    }
    const directId = await chat();
    const thread = (await state()).threads.find(
      (item) => item.taskId === taskId
    )!;
    await store.edit('alice', snapshot => {
      for (const item of snapshot.threads.filter(item => item.origin === 'task')) {
        item.status = 'blocked';
        item.question = agentQuestionSchema.parse({ id: randomUUID(), runId: item.runId, threadId: item.id,
          header: 'Continue', question: 'Continue?', options: [], allowCustomAnswer: true,
          questions: [{ id: 'continue', header: null, question: 'Continue?', options: [], allowCustomAnswer: true }], createdAt: item.updatedAt });
      }
    });
    const archive = command(action === 'chat.archive' ? { type: action, threadId: thread.id } : { type: action, taskId });
    expect(await store.command('alice', archive)).toMatchObject({
      status: 'completed'
    });
    expect(await store.command('alice', archive)).toMatchObject({
      status: 'completed'
    });
    const archived = await state();
    expect(archived.tasks.map((item) => item.id)).toEqual([unrelatedId]);
    expect(
      archived.threads
        .filter((item) => item.origin === 'task')
        .every((item) => item.archivedAt && item.status === 'ready' && item.question === null && item.activity === null)
    ).toBe(true);
    expect(
      archived.threads.find((item) => item.id === thread.id)?.messages
    ).toHaveLength(thread.messages.length);
    expect(
      archived.threads.find((item) => item.id === directId)?.archivedAt
    ).toBeNull();
    expect(await store.claim()).toBeNull();
    await store.command(
      'alice',
      command({ type: 'chat.archive', threadId: directId })
    );
    expect((await state()).tasks.map((item) => item.id)).toEqual([unrelatedId]);
  });

  it('starts Off, defaults to Cloud, and denies writes without account Pro', async () => {
    expect((await state()).mode).toBe('off');
    expect(await store.status('alice', true)).toMatchObject({
      pro: false,
      executionTarget: 'cloud',
      dailyLimitUsd: 10
    });
    await expect(
      store.command(
        'alice',
        command({
          type: 'task.create',
          taskId: randomUUID(),
          input: { title: 'A' }
        })
      )
    ).rejects.toMatchObject({ status: 403 });
  });
  it('deduplicates commands, scopes IDs to accounts, and detects stale updates', async () => {
    await store.settings('alice', { pro: true });
    await store.settings('bob', { pro: true });
    const id = randomUUID();
    const create = command({
      type: 'task.create',
      taskId: id,
      input: { title: 'Original' }
    });
    await store.command('alice', create);
    await store.command('alice', create);
    expect((await state()).tasks).toHaveLength(1);
    expect((await state('bob')).tasks).toHaveLength(0);
    const before = (await state()).tasks[0]!;
    expect(
      await store.command(
        'bob',
        command({
          type: 'task.update',
          taskId: id,
          expectedUpdatedAt: before.updatedAt,
          patch: { title: 'Stolen' }
        })
      )
    ).toMatchObject({ status: 'conflict' });
    await store.command(
      'alice',
      command({
        type: 'task.update',
        taskId: id,
        expectedUpdatedAt: before.updatedAt,
        patch: { title: 'Updated' }
      })
    );
    expect(
      await store.command(
        'alice',
        command({
          type: 'task.update',
          taskId: id,
          expectedUpdatedAt: 'old',
          patch: { title: 'Stale' }
        })
      )
    ).toMatchObject({ status: 'conflict' });
    expect((await state()).tasks[0]!.title).toBe('Updated');
  });
  it('merges independent device edits without resurrecting deleted tasks or erasing cloud chats', async () => {
    await store.settings('alice', { pro: true });
    const id = randomUUID();
    await store.command(
      'alice',
      command({ type: 'task.create', taskId: id, input: { title: 'Original' } })
    );
    const base = await state();
    const incoming = structuredClone(base);
    incoming.tasks[0]!.notes = 'Desktop notes';
    await store.command(
      'alice',
      command({
        type: 'task.update',
        taskId: id,
        expectedUpdatedAt: base.tasks[0]!.updatedAt,
        patch: { title: 'Phone title' }
      })
    );
    await chat();
    const exchange = {
      id: randomUUID(),
      desktopId: randomUUID(),
      name: 'Mac',
      base,
      snapshot: incoming
    };
    const result = await store.exchange('alice', exchange);
    expect(result.snapshot.tasks[0]).toMatchObject({
      title: 'Phone title',
      notes: 'Desktop notes'
    });
    expect(result.snapshot.threads).toHaveLength(1);
    expect(result.conflicts).toEqual([]);
    expect(await store.exchange('alice', exchange)).toEqual(result);
    const deleted = structuredClone(result.snapshot);
    deleted.tasks = [];
    const merged = mergeCloudSnapshot(
      deleted,
      result.snapshot,
      result.snapshot
    );
    expect(merged.snapshot.tasks).toEqual([]);
  });
  it('keeps conflicting shared edits and records exactly which field needs attention', async () => {
    await store.settings('alice', { pro: true });
    await store.command(
      'alice',
      command({
        type: 'task.create',
        taskId: randomUUID(),
        input: { title: 'Original' }
      })
    );
    const base = await state();
    const cloud = structuredClone(base);
    const desktop = structuredClone(base);
    cloud.tasks[0]!.title = 'Cloud';
    desktop.tasks[0]!.title = 'Desktop';
    const result = mergeCloudSnapshot(cloud, base, desktop);
    expect(result.snapshot.tasks[0]!.title).toBe('Cloud');
    expect(result.conflicts).toEqual([
      `workspace/tasks/${base.tasks[0]!.id}/title`
    ]);
  });
  it('switches execution location without changing task/chat identity and keeps data after Pro is disabled', async () => {
    await store.settings('alice', { pro: true });
    const threadId = await chat();
    await store.command(
      'alice',
      command({ type: 'chat.send', threadId, message: 'Hi', files: [] })
    );
    const before = await state();
    await store.settings('alice', { executionTarget: 'computer' });
    expect((await state()).threads.map((thread) => thread.id)).toEqual(
      before.threads.map((thread) => thread.id)
    );
    await store.settings('alice', { pro: false });
    expect((await state()).threads[0]!.messages).toHaveLength(2);
    expect((await state()).threads[0]!.status).toBe('ready');
    expect(await store.claim()).toBeNull();
  });
  it('creates colored agents and edits them without resetting model or welcome settings', async () => {
    await store.settings('alice', { pro: true });
    const routes = createMobileRoutes(
      store,
      async () => ({ id: 'alice', name: null, email: null, avatarUrl: null }),
      true,
      {} as typeof composioConnectorService
    );
    const save = (input: unknown) =>
      routes.request('/agents', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(input)
      });
    const response = await save({
      name: 'Research',
      instructions: 'Find sources',
      color: '#A96BFF'
    });
    expect(response.status).toBe(200);
    const { id } = (await response.json()) as { id: string };
    await store.edit('alice', (snapshot) => {
      const agent = snapshot.agents.find((agent) => agent.id === id)!;
      agent.modelOverride = 'test/custom-model';
      agent.welcomeMessage = 'Welcome back';
      agent.emoji = '🔎';
    });
    expect(
      (
        await save({
          id,
          name: 'Writer',
          instructions: 'Write clearly',
          color: '#56FF61'
        })
      ).status
    ).toBe(200);
    expect(
      (await state()).agents.find((agent) => agent.id === id)
    ).toMatchObject({
      name: 'Writer',
      instructions: 'Write clearly',
      color: '#56FF61',
      modelOverride: 'test/custom-model',
      welcomeMessage: 'Welcome back',
      emoji: '🔎'
    });
    expect(
      (await save({ id, name: 'Writer', instructions: 'Keep the color' }))
        .status
    ).toBe(200);
    expect((await state()).agents.find((agent) => agent.id === id)?.color).toBe(
      '#56FF61'
    );
    expect(
      (await save({ id: randomUUID(), name: 'Missing', instructions: '' }))
        .status
    ).toBe(404);
    expect(
      (await save({ name: 'Bad color', instructions: '', color: 'invalid' }))
        .status
    ).toBe(400);
    await store.settings('alice', { pro: false });
    expect(
      (await save({ id, name: 'Read only', instructions: '' })).status
    ).toBe(403);
  });

  it('checks backend entitlement even if the request body claims to be Pro', async () => {
    const routes = createMobileRoutes(
      store,
      async (headers) =>
        headers.get('authorization') === 'Bearer alice'
          ? { id: 'alice', name: null, email: null, avatarUrl: null }
          : Response.json({}, { status: 401 }),
      true,
      {} as typeof composioConnectorService
    );
    expect((await routes.request('/account')).status).toBe(401);
    const response = await routes.request('/commands', {
      method: 'POST',
      headers: {
        authorization: 'Bearer alice',
        'content-type': 'application/json'
      },
      body: JSON.stringify({
        ...command({
          type: 'task.create',
          taskId: randomUUID(),
          input: { title: 'No' }
        }),
        pro: true,
        userId: 'bob'
      })
    });
    expect(response.status).toBe(403);
  });
});

describe('durable cloud runs and spending', () => {
  beforeEach(async () => {
    await store.settings('alice', { pro: true });
  });
  it('persists a queued run and finishes without a connected phone', async () => {
    const threadId = await chat();
    const send = command({
      type: 'chat.send',
      threadId,
      message: 'Hello',
      thinking: 'deep',
      files: []
    });
    await store.command('alice', send);
    await store.command('alice', send);
    const restored = new CloudStore(database.pool);
    const model: CloudModel = {
      configured: true,
      step: async (_job, input) => {
        expect(input.thinking).toBe('deep');
        return {
          text: 'Hello from Cloud',
          messages: input.messages,
          finished: true
        };
      }
    };
    const worker = new CloudWorker(restored, model, {
      execute: async () => ({})
    });
    await worker.tick();
    expect((await state()).threads[0]).toMatchObject({
      status: 'ready', thinking: 'deep'
    });
    expect((await state()).threads[0]!.messages.at(-1)!.content).toBe(
      'Hello from Cloud'
    );
    const jobs = await database.pool.query('SELECT * FROM cloud_jobs', []);
    expect(jobs.rows).toHaveLength(1);
    const notifications = await database.pool.query(
      'SELECT * FROM cloud_notifications',
      []
    );
    expect(notifications.rows).toHaveLength(1);
  });
  it('blocks duplicate active runs and never replays a tool with uncertain completion', async () => {
    const threadId = await chat();
    await store.command(
      'alice',
      command({ type: 'chat.send', threadId, message: 'Run', files: [] })
    );
    expect(
      await store.command(
        'alice',
        command({
          type: 'chat.send',
          threadId,
          message: 'Duplicate',
          files: []
        })
      )
    ).toMatchObject({ status: 'conflict' });
    const job = (await store.claim())!;
    let effects = 0;
    await expect(
      store.tool(job, 'call-1', async () => {
        effects++;
        throw new Error('Unknown delivery');
      })
    ).rejects.toThrow();
    await expect(
      store.tool(job, 'call-1', async () => {
        effects++;
        return {};
      })
    ).rejects.toMatchObject({ status: 409 });
    expect(effects).toBe(1);
  });
  it('reserves spending atomically, retains unknown costs, and rejects spending over $10', async () => {
    const threadId = await chat();
    await store.command(
      'alice',
      command({ type: 'chat.send', threadId, message: 'Budget', files: [] })
    );
    const job = (await store.claim())!;
    const results = await Promise.allSettled(
      Array.from({ length: 6 }, () => store.reserve(job, 2))
    );
    expect(results.filter((item) => item.status === 'fulfilled')).toHaveLength(
      5
    );
    expect(results.filter((item) => item.status === 'rejected')).toHaveLength(
      1
    );
    const id = results.find((item) => item.status === 'fulfilled')!;
    if (id.status === 'fulfilled') {
      await store.settle(id.value, undefined);
      expect((await store.status('alice', true)).dailySpentUsd).toBe(10);
      await store.settle(id.value, 0.25);
    }
    expect((await store.status('alice', true)).dailySpentUsd).toBe(8.25);
    await expect(store.reserve(job, 2)).rejects.toMatchObject({ status: 429 });
    await expect(store.reserve(job, 2)).rejects.toThrow(
      /try again in about \d+ hours?/
    );
    await expect(store.reserve(job, 11)).rejects.toThrow(
      'Please try a smaller request or fewer attachments.'
    );
  });
  it('does not plan or run tasks while the shared agent mode is Off', async () => {
    await store.command(
      'alice',
      command({
        type: 'task.create',
        taskId: randomUUID(),
        input: { title: 'Research a topic' }
      })
    );
    const worker = new CloudWorker(
      store,
      {
        configured: true,
        step: async () => {
          throw new Error('Must not call a model');
        }
      },
      { execute: async () => ({}) }
    );
    await worker.tick();
    expect(
      (await database.pool.query('SELECT * FROM cloud_jobs', [])).rows
    ).toEqual([]);
  });

  it('reconciles unknown holds once, leaves active holds alone, and preserves known charges', async () => {
    const threadId = await chat();
    await store.command(
      'alice',
      command({ type: 'chat.send', threadId, message: 'Hello', files: [] })
    );
    const job = (await store.claim())!;
    const unknown = await store.reserve(job, 2);
    const active = await store.reserve(job, 2);
    await store.recordGeneration(unknown, 'gen-unknown');
    await store.recordGeneration(active, 'gen-active');
    await store.markUnknownCost(unknown);
    expect(await store.costsToReconcile()).toEqual([
      { id: unknown, generation_id: 'gen-unknown' }
    ]);
    expect(await store.costsToReconcile()).toEqual([]);
    await store.settle(unknown, 0.01);
    await store.settle(unknown, 0, 'rejected');
    expect((await store.status('alice', true)).dailySpentUsd).toBe(2.01);
    await database.pool.query(
      "UPDATE cloud_spend SET created_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-20 minutes') WHERE id = $1",
      [active]
    );
    expect(await store.costsToReconcile()).toEqual([
      { id: active, generation_id: 'gen-active' }
    ]);
  });
});

describe('cloud agent tools', () => {
  beforeEach(async () => {
    await store.settings('alice', { pro: true });
  });

  it.each(['budget', 'provider', 'failed-outcome', 'missing-outcome'])(
    'keeps unsuccessful work out of review (%s) and lets the user retry',
    async (failure) => {
      const taskId = randomUUID();
      await store.command(
        'alice',
        command({
          type: 'task.create',
          taskId,
          input: { title: 'Check AI news' }
        })
      );
      await store.command(
        'alice',
        command({
          type: 'task.suggestion',
          taskId,
          expectedUpdatedAt: (await state()).tasks[0]!.updatedAt,
          action: 'accept'
        })
      );
      let retry = false;
      const model: CloudModel = {
        configured: true,
        step: async (job, input) => {
          if (retry)
            return {
              text: 'Here is the news.\nDONY_TASK_OUTCOME: review',
              messages: input.messages,
              finished: true
            };
          if (failure === 'budget') {
            if (input.search)
              throw new CloudError(
                429,
                'Dony has reached today’s usage limit. Your task is still saved.'
              );
            await input.tools.web_search!.execute!(
              { query: 'AI news' },
              { toolCallId: 'search', messages: [], context: undefined }
            );
          }
          if (failure === 'provider')
            throw new Error('SECRET provider internals');
          return {
            text:
              'I couldn’t finish.' +
              (failure === 'failed-outcome'
                ? '\nDONY_TASK_OUTCOME: failed'
                : ''),
            messages: input.messages,
            finished: true
          };
        }
      };
      const worker = new CloudWorker(store, model, {
        execute: async () => ({})
      });
      await worker.tick();
      let snapshot = await state();
      expect(snapshot.tasks[0]).toMatchObject({
        status: 'todo',
        proactiveExecutionStatus: 'failed'
      });
      expect(snapshot.threads[0]!.status).toBe('failed');
      expect(snapshot.results).toEqual([]);
      const content = snapshot.threads[0]!.messages.at(-1)!.content;
      expect(content).not.toMatch(
        /DONY_TASK_OUTCOME|SECRET|OpenRouter|429|UTC/
      );
      if (failure === 'budget') expect(content).toContain('usage limit');
      retry = true;
      await store.command(
        'alice',
        command({
          type: 'chat.send',
          threadId: snapshot.threads[0]!.id,
          message: 'Please try again.',
          files: []
        })
      );
      await worker.tick();
      snapshot = await state();
      expect(snapshot.results).toHaveLength(1);
      expect(snapshot.results[0]).toMatchObject({
        outcome: 'review',
        preview: 'Here is the news.'
      });
      expect(snapshot.tasks[0]!.status).toBe('todo');
      // A failed revision must not revive an older approval button.
      retry = false;
      await store.command(
        'alice',
        command({
          type: 'chat.send',
          threadId: snapshot.threads[0]!.id,
          message: 'Please include sources.',
          files: []
        })
      );
      await worker.tick();
      expect((await state()).results[0]!.dismissedAt).not.toBeNull();
      expect(
        await store.command(
          'alice',
          command({
            type: 'task.review',
            resultId: snapshot.results[0]!.id,
            action: 'accept',
            feedback: ''
          })
        )
      ).toMatchObject({ status: 'conflict' });
    }
  );
  it('pauses for a question, resumes after an answer, and publishes a reviewable result with an owned file', async () => {
    const taskId = randomUUID();
    await store.command(
      'alice',
      command({
        type: 'task.create',
        taskId,
        input: { title: 'Write a report' }
      })
    );
    let task = (await state()).tasks[0]!;
    await store.command(
      'alice',
      command({
        type: 'task.suggestion',
        taskId,
        expectedUpdatedAt: task.updatedAt,
        action: 'accept'
      })
    );
    let stage = 'ask';
    const model: CloudModel = {
      configured: true,
      step: async (_job, input) => {
        if (stage === 'ask') {
          await input.tools.ask_user!.execute!(
            { question: 'Which audience?', options: ['Team', 'Public'] },
            { toolCallId: 'ask', messages: [] }
          );
          return {
            text: 'I need the audience.',
            messages: input.messages,
            finished: false
          };
        }
        await input.tools.publish_output!.execute!(
          { name: 'Report', markdown: '# Report\nFor the team.' },
          { toolCallId: 'publish', messages: [] }
        );
        return {
          text: 'The report is ready.\nDONY_TASK_OUTCOME: review',
          messages: input.messages,
          finished: true
        };
      }
    };
    const worker = new CloudWorker(store, model, { execute: async () => ({}) });
    await worker.tick();
    let snapshot = await state();
    expect(snapshot.threads[0]?.status).toBe('blocked');
    const question = snapshot.threads[0]!.question!;
    expect(await store.claim()).toBeNull();
    stage = 'finish';
    await store.command(
      'alice',
      command({
        type: 'question.answer',
        questionId: question.id,
        response: {
          action: 'accept',
          files: [],
          answers: [
            { questionId: 'answer', type: 'option', selectedOptionId: '1' }
          ]
        }
      })
    );
    await worker.tick();
    snapshot = await state();
    expect(snapshot.tasks[0]?.status).toBe('todo');
    expect(snapshot.results[0]?.outcome).toBe('review');
    expect(
      snapshot.threads[0]?.messages.find((message) => message.questionAnswer)
        ?.questionAnswer?.answers[0]?.answer
    ).toBe('Team');
    const result = snapshot.results[0]!;
    const file = await store.command(
      'alice',
      command({ type: 'artifact.read', resultId: result.id, index: 0 })
    );
    expect(file.file?.name).toBe('Report.md');
    expect(Buffer.from(file.file!.base64, 'base64').toString()).toContain(
      'For the team.'
    );
    await store.settings('bob', { pro: true });
    expect(
      await store.command(
        'bob',
        command({ type: 'artifact.read', resultId: result.id, index: 0 })
      )
    ).toMatchObject({ status: 'failed' });
    await store.command(
      'alice',
      command({
        type: 'task.review',
        resultId: result.id,
        action: 'accept',
        feedback: ''
      })
    );
    task = (await state()).tasks[0]!;
    expect(task.status).toBe('done');
  });

  it('plans Suggestions without executing and runs Proactive suggestions once', async () => {
    const taskId = randomUUID();
    await store.command(
      'alice',
      command({
        type: 'task.create',
        taskId,
        input: { title: 'Research a topic' }
      })
    );
    await store.command(
      'alice',
      command({ type: 'mode.set', expectedMode: 'off', mode: 'suggest' })
    );
    let executions = 0;
    const model: CloudModel = {
      configured: true,
      step: async (job, input) => {
        if (job.kind === 'plan')
          await input.tools.classify!.execute!(
            { canComplete: true, agentId: null },
            { toolCallId: 'classify', messages: [] }
          );
        else executions++;
        return {
          text:
            job.kind === 'plan'
              ? ''
              : 'Research complete.\nDONY_TASK_OUTCOME: review',
          messages: input.messages,
          finished: true
        };
      }
    };
    const worker = new CloudWorker(store, model, { execute: async () => ({}) });
    await worker.tick();
    expect((await state()).tasks[0]?.proactiveSuggestionPending).toBe(true);
    expect(executions).toBe(0);
    await store.command(
      'alice',
      command({ type: 'mode.set', expectedMode: 'suggest', mode: 'proactive' })
    );
    await worker.tick();
    await worker.tick();
    expect(executions).toBe(1);
    expect((await state()).results).toHaveLength(1);
  });

  it('stops expired runs without replaying external actions and clears failed planning', async () => {
    const taskId = randomUUID();
    await store.command(
      'alice',
      command({ type: 'task.create', taskId, input: { title: 'Research' } })
    );
    await store.command(
      'alice',
      command({ type: 'mode.set', expectedMode: 'off', mode: 'suggest' })
    );
    const worker = new CloudWorker(
      store,
      {
        configured: true,
        step: async () => {
          throw new Error('Must not replay');
        }
      },
      { execute: async () => ({}) }
    );
    await worker.schedulePlans();
    const job = (await store.claim())!;
    await database.pool.query(
      "UPDATE cloud_jobs SET lease_until = strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-1 minute') WHERE id = $1",
      [job.id]
    );
    expect(await store.claim()).toBeNull();
    expect((await state()).tasks[0]?.proactivePlanningStatus).toBe('failed');
  });
});
