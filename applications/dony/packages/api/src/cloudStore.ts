import { randomUUID } from 'node:crypto';
import type { BillingStore } from './billing/store';
import { WorkspaceChanges } from './workspaceChanges';
import { D1Transaction, type DonyDatabase, type QueryClient } from './database';
import type { ModelMessage } from 'ai';
import {
  cloudSnapshotSchema,
  emptyCloudSnapshot,
  mergeCloudSnapshot,
  type CloudCommand,
  type CloudExchange,
  type CloudExecutionTarget,
  type CloudSnapshot,
  type CloudStatus,
  type CompanionReceipt
} from '@dony/domain';
import {
  applyCloudCommand,
  CloudError,
  cloudNow,
  type CloudJobDraft
} from './cloudCommands';

export type CloudWorkspaceRow = {
  id: string;
  user_id: string;
  pro: boolean;
  execution_target: CloudExecutionTarget;
  snapshot: CloudSnapshot;
  revision: number;
};
export type CloudJob = {
  id: string;
  workspace_id: string;
  user_id: string;
  thread_id: string;
  assistant_message_id: string;
  kind: 'chat' | 'plan' | 'onboarding';
  state: 'queued' | 'running' | 'blocked' | 'completed' | 'failed' | 'canceled';
  messages: ModelMessage[];
  files: CloudJobDraft['files'];
  lease: string | null;
  step: number;
};
export const cloudDailyLimitUsd = 10;

export async function deleteDonyAccountData(
  pool: DonyDatabase,
  userId: string
): Promise<void> {
  await pool.transaction(async (client) => {
    const billing = await client.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'billing_accounts'");
    if (billing.rows.length) {
      // Retain anonymous transaction IDs to prevent refunded/restored purchases
      // being claimed again; remove their link to the deleted account.
      await client.query('UPDATE billing_accounts SET user_id = NULL WHERE user_id = $1', [userId]);
    }
    const workspace = await client.query<{ id: string }>(
      'SELECT id FROM cloud_workspaces WHERE user_id = $1',
      [userId]
    );
    const workspaceId = workspace.rows[0]?.id;

    if (workspaceId) {
      await client.query(
        'DELETE FROM cloud_tool_calls WHERE job_id IN (SELECT id FROM cloud_jobs WHERE workspace_id = $1)',
        [workspaceId]
      );
      await client.query(
        'DELETE FROM cloud_spend WHERE job_id IN (SELECT id FROM cloud_jobs WHERE workspace_id = $1)',
        [workspaceId]
      );
      for (const table of [
        'cloud_notifications',
        'cloud_artifacts',
        'cloud_push_devices',
        'cloud_receipts',
        'cloud_jobs',
        'cloud_desktops'
      ]) {
        await client.query(`DELETE FROM ${table} WHERE workspace_id = $1`, [
          workspaceId
        ]);
      }
      await client.query('DELETE FROM cloud_workspaces WHERE id = $1', [
        workspaceId
      ]);
    }

    await client.query('DELETE FROM companion_desktops WHERE user_id = $1', [
      userId
    ]);
    await client.query(
      "DELETE FROM mobile_auth_handoffs WHERE user_data->>'id' = $1",
      [userId]
    );
  });
}

export class CloudStore {
  readonly changes = new WorkspaceChanges();
  private readonly changedUsers = new WeakMap<D1Transaction, Set<string>>();
  private readonly transactionWorkspaces = new WeakMap<D1Transaction, Map<string, CloudWorkspaceRow>>();
  onWorkAvailable: () => void = () => {};
  onNotificationsAvailable: () => void = () => {};
  private readonly planningInputs = new WeakMap<CloudWorkspaceRow, string>();
  constructor(readonly pool: DonyDatabase, readonly billing?: BillingStore) {}

  private planningKey(workspace: CloudWorkspaceRow) {
    return JSON.stringify([workspace.pro, workspace.execution_target, workspace.snapshot.mode,
      workspace.snapshot.tasks.map((task) => [task.id, task.title, task.notes, task.dueDate,
        task.status, task.deletedAt, task.proactivePlanningStatus, task.proactiveExecutionStatus,
        task.proactiveSuggestionPending, task.proactiveEvaluationKey])]);
  }

  private rememberPlanning(workspace: CloudWorkspaceRow) {
    this.planningInputs.set(workspace, this.planningKey(workspace));
    return workspace;
  }

  async migrate() {
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS cloud_workspaces (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL UNIQUE, pro BOOLEAN NOT NULL DEFAULT false,
        execution_target TEXT NOT NULL DEFAULT 'cloud', snapshot TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS cloud_planning_pending (
        workspace_id TEXT PRIMARY KEY REFERENCES cloud_workspaces(id) ON DELETE CASCADE
      );
      CREATE TABLE IF NOT EXISTS cloud_recovery (
        id TEXT PRIMARY KEY, next_check_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS cloud_receipts (
        workspace_id TEXT NOT NULL REFERENCES cloud_workspaces(id), id TEXT NOT NULL,
        receipt TEXT NOT NULL, PRIMARY KEY(workspace_id, id)
      );
      CREATE TABLE IF NOT EXISTS cloud_desktops (
        id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL REFERENCES cloud_workspaces(id),
        name TEXT NOT NULL, last_seen_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')), last_exchange_id TEXT, last_exchange_reply TEXT
      );
      CREATE TABLE IF NOT EXISTS cloud_jobs (
        id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL REFERENCES cloud_workspaces(id),
        thread_id TEXT NOT NULL, assistant_message_id TEXT NOT NULL, kind TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'queued', messages TEXT NOT NULL DEFAULT '[]',
        files TEXT NOT NULL DEFAULT '[]', lease TEXT, lease_until TEXT,
        step INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')), error TEXT
      );
      CREATE INDEX IF NOT EXISTS cloud_jobs_ready ON cloud_jobs(state, created_at);
      CREATE INDEX IF NOT EXISTS cloud_jobs_expired ON cloud_jobs(state, lease_until);
      CREATE UNIQUE INDEX IF NOT EXISTS cloud_jobs_one_active ON cloud_jobs(workspace_id, thread_id) WHERE state IN ('queued', 'running');
      CREATE TABLE IF NOT EXISTS cloud_spend (
        id TEXT PRIMARY KEY, job_id TEXT NOT NULL REFERENCES cloud_jobs(id),
        day DATE NOT NULL DEFAULT (date('now')),
        reserved_micros INTEGER NOT NULL, charged_micros INTEGER, generation_id TEXT, cost_status TEXT NOT NULL DEFAULT 'reserved', checked_at TEXT, created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
      );

      UPDATE cloud_spend SET cost_status = 'settled' WHERE charged_micros IS NOT NULL AND cost_status = 'reserved';
      UPDATE cloud_spend SET cost_status = 'unknown' WHERE charged_micros IS NULL AND cost_status = 'reserved'
        AND job_id IN (SELECT id FROM cloud_jobs WHERE state NOT IN ('queued', 'running'));
      CREATE TABLE IF NOT EXISTS cloud_tool_calls (
        job_id TEXT NOT NULL REFERENCES cloud_jobs(id), id TEXT NOT NULL,
        state TEXT NOT NULL, result TEXT, PRIMARY KEY(job_id, id)
      );
      CREATE TABLE IF NOT EXISTS cloud_push_devices (
        workspace_id TEXT NOT NULL REFERENCES cloud_workspaces(id), token TEXT NOT NULL,
        environment TEXT NOT NULL, PRIMARY KEY(workspace_id, token)
      );
      CREATE TABLE IF NOT EXISTS cloud_notifications (
        id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL REFERENCES cloud_workspaces(id),
        thread_id TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')), sent_at TEXT
      );
      CREATE INDEX IF NOT EXISTS cloud_notifications_pending ON cloud_notifications(created_at) WHERE sent_at IS NULL;
      CREATE TABLE IF NOT EXISTS cloud_artifacts (
        id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL REFERENCES cloud_workspaces(id),
        thread_id TEXT NOT NULL, file TEXT NOT NULL
      );
    `);
    // Backfill existing workspaces exactly once, atomically with its marker.
    await this.pool.send([
      { sql: `INSERT OR IGNORE INTO cloud_planning_pending(workspace_id)
          SELECT id FROM cloud_workspaces WHERE NOT EXISTS
          (SELECT 1 FROM cloud_recovery WHERE id = 'planning-backfill-v1')` },
      { sql: "INSERT OR IGNORE INTO cloud_recovery(id, next_check_at) VALUES ('planning-backfill-v1', 0)" }
    ]);
    await this.pool.trackTables(['cloud_planning_pending', 'cloud_workspaces', 'cloud_receipts', 'cloud_desktops', 'cloud_jobs', 'cloud_spend', 'cloud_tool_calls', 'cloud_push_devices', 'cloud_notifications', 'cloud_artifacts']);
  }

  async transaction<T>(run: (client: D1Transaction) => Promise<T>): Promise<T> {
    let committed: D1Transaction | undefined;
    const result = await this.pool.transaction(async (client) => {
      const result = await run(client);
      committed = client;
      return result;
    });
    // Notify only after the successful attempt commits. Failed/retried attempts
    // must never wake a consumer before its work is durable.
    const writes = committed?.writes ?? [];
    if (committed)
      for (const userId of this.changedUsers.get(committed) ?? []) this.changes.publish(userId);
    if (writes.some(({ sql }) => /^INSERT.*INTO cloud_(jobs|planning_pending)\b/i.test(sql)))
      this.onWorkAvailable();
    if (writes.some(({ sql }) => /^INSERT INTO cloud_notifications\b/i.test(sql)))
      this.onNotificationsAvailable();
    return result;
  }

  async workspace(
    client: QueryClient,
    userId: string,
    _lock = false,
    readBilling = true
  ): Promise<CloudWorkspaceRow> {
    const existing = await client.query<CloudWorkspaceRow>(
      'SELECT * FROM cloud_workspaces WHERE user_id = $1', [userId]
    );
    if (existing.rows[0]) {
      const workspace = existing.rows[0];
      if (this.billing && readBilling) {
        const access = await this.billing.read(client, userId);
        workspace.pro = Boolean(access.active) || access.extraRemaining > 0;
      }
      return this.rememberPlanning(workspace);
    }
    const id = randomUUID();
    const initial = emptyCloudSnapshot();
    initial.agents.push({
      id: randomUUID(),
      name: 'Dony',
      emoji: '✳️',
      color: '#2080FB',
      instructions: 'Help the user with tasks, research, and connected apps.',
      welcomeMessage: null,
      modelOverride: null,
      updatedAt: cloudNow()
    });
    await client.query(
      'INSERT INTO cloud_workspaces(id, user_id, snapshot) VALUES ($1, $2, $3) ON CONFLICT(user_id) DO NOTHING',
      [id, userId, JSON.stringify(initial)]
    );
    if (client instanceof D1Transaction) {
      return { id, user_id: userId, pro: false, execution_target: 'cloud', snapshot: initial, revision: 0 };
    }
    const result = await client.query<CloudWorkspaceRow>('SELECT * FROM cloud_workspaces WHERE user_id = $1', [userId]);
    return result.rows[0]!;
  }

  async save(client: D1Transaction, workspace: CloudWorkspaceRow, schedulePlanning = true) {
    for (const thread of workspace.snapshot.threads) {
      const task = workspace.snapshot.tasks.find(
        (item) => item.id === thread.taskId
      );
      thread.sidebarExpiresAt =
        thread.origin === 'task' && task?.status === 'done' && thread.viewedAt
          ? new Date(Date.parse(thread.viewedAt) + 86_400_000).toISOString()
          : null;
    }
    workspace.snapshot = cloudSnapshotSchema.parse(workspace.snapshot);
    const key = this.planningKey(workspace);
    if (schedulePlanning && key !== this.planningInputs.get(workspace)) {
      await client.query('INSERT OR IGNORE INTO cloud_planning_pending(workspace_id) VALUES ($1)', [workspace.id]);
    }
    this.planningInputs.set(workspace, key);
    workspace.revision += 1;
    await client.query(
      'UPDATE cloud_workspaces SET snapshot = $2, revision = $3, pro = $4, execution_target = $5 WHERE id = $1',
      [
        workspace.id,
        JSON.stringify(workspace.snapshot),
        workspace.revision,
        workspace.pro,
        workspace.execution_target
      ]
    );
    if (client instanceof D1Transaction) {
      const users = this.changedUsers.get(client) ?? new Set<string>();
      users.add(workspace.user_id);
      this.changedUsers.set(client, users);
    }
  }

  requirePro(workspace: CloudWorkspaceRow) {
    if (!workspace.pro)
      throw new CloudError(
        403,
        'Enable Dony Pro to change your cloud workspace or run cloud agents.'
      );
  }

  async status(userId: string, configured: boolean): Promise<CloudStatus> {
    const workspace = await this.workspace(this.pool, userId, false, false);
    if (this.billing) {
      const billing = await this.billing.status(userId);
      return { workspaceId: workspace.id, pro: billing.canUseRemoteDesktop || billing.extraRemainingPercent > 0, executionTarget: workspace.execution_target,
        dailyLimitUsd: 0, dailySpentUsd: 0, resetsAt: billing.resetsAt ?? '', configured, billing };
    }
    const { rows } = await this.pool.query<{ spent: string }>(
      "SELECT COALESCE(SUM(COALESCE(charged_micros, reserved_micros)), 0) AS spent FROM cloud_spend WHERE day = date('now')",
      []
    );
    const tomorrow = new Date();
    tomorrow.setUTCHours(24, 0, 0, 0);
    return {
      workspaceId: workspace.id,
      pro: workspace.pro,
      executionTarget: workspace.execution_target,
      dailyLimitUsd: cloudDailyLimitUsd,
      dailySpentUsd: Number(rows[0]!.spent) / 1_000_000,
      resetsAt: tomorrow.toISOString(),
      configured
    };
  }

  async settings(
    userId: string,
    patch: {
      pro?: boolean | undefined;
      executionTarget?: CloudExecutionTarget | undefined;
    }
  ) {
    if (this.billing && patch.pro !== undefined)
      throw new CloudError(403, 'Manage your subscription in Dony on your iPhone.');
    await this.transaction(async (client) => {
      const workspace = await this.workspace(client, userId, true);
      if (patch.pro !== undefined) workspace.pro = patch.pro;
      if (patch.executionTarget !== undefined) {
        if (!this.billing) this.requirePro(workspace);
        workspace.execution_target = patch.executionTarget;
      }
      if (patch.pro === false) {
        const canceled = await client.query<{
          id: string;
          thread_id: string;
          kind: string;
        }>(
          "SELECT id, thread_id, kind FROM cloud_jobs WHERE workspace_id = $1 AND state IN ('queued', 'running', 'blocked')",
          [workspace.id]
        );
        await client.query("UPDATE cloud_jobs SET state = 'canceled' WHERE workspace_id = $1 AND state IN ('queued', 'running', 'blocked')", [workspace.id]);
        const runIds = new Set(canceled.rows.map((job) => job.id));
        for (const thread of workspace.snapshot.threads) {
          if (!thread.runId || !runIds.has(thread.runId)) continue;
          thread.status = 'ready';
          thread.activity = null;
          thread.question = null;
          for (const message of thread.messages)
            if (message.status === 'pending') message.status = 'complete';
          const task = workspace.snapshot.tasks.find(
            (item) => item.id === thread.taskId
          );
          if (task) task.proactiveExecutionStatus = null;
        }
        for (const job of canceled.rows.filter((job) => job.kind === 'plan')) {
          const task = workspace.snapshot.tasks.find(
            (item) => item.id === job.thread_id
          );
          if (task) {
            task.proactivePlanningStatus = null;
            task.proactiveEvaluationKey = null;
          }
        }
      }
      await this.save(client, workspace);
    });
  }

  async state(userId: string, revision: number, commandIds: string[]) {
    return this.transaction(async (client) => {
      const workspace = await this.workspace(client, userId, true);
      const { rows } = await client.query<{ receipt: CompanionReceipt }>(
        'SELECT receipt FROM cloud_receipts WHERE workspace_id = $1 AND id IN (SELECT value FROM json_each($2))',
        [workspace.id, commandIds]
      );
      return {
        revision: workspace.revision,
        desktopOnline: true,
        pro: workspace.pro,
        executionTarget: workspace.execution_target,
        snapshot: revision === workspace.revision ? null : workspace.snapshot,
        receipts: rows.map((item) => item.receipt)
      };
    });
  }

  async insertJob(client: D1Transaction, workspaceId: string, job: CloudJobDraft) {
    await client.query(
      'INSERT INTO cloud_jobs(id, workspace_id, thread_id, assistant_message_id, kind, files) VALUES($1,$2,$3,$4,$5,$6)',
      [
        job.id,
        workspaceId,
        job.threadId,
        job.assistantMessageId,
        job.kind,
        JSON.stringify(job.files)
      ]
    );
  }

  async command(userId: string, command: CloudCommand) {
    return this.transaction(async (client) => {
      const workspace = await this.workspace(client, userId, true);
      const saved = await client.query<{ receipt: CompanionReceipt }>(
        'SELECT receipt FROM cloud_receipts WHERE workspace_id = $1 AND id = $2',
        [workspace.id, command.id]
      );
      if (saved.rows[0]) return saved.rows[0].receipt;
      const reading = ['chat.viewed', 'artifact.read', 'run.stop'].includes(
        command.action.type
      );
      if (!reading && !this.billing) this.requirePro(workspace);
      if (
        command.executionTarget === 'computer' &&
        [
          'chat.send',
          'task.suggestion',
          'question.answer',
          'task.review'
        ].includes(command.action.type)
      ) {
        throw new CloudError(
          409,
          'This action is unavailable. Check where your agents run in Settings.'
        );
      }
      const before = new Map(
        workspace.snapshot.tasks.map((task) => [task.id, task.updatedAt])
      );
      let receipt: CompanionReceipt;
      const backup = structuredClone(workspace.snapshot);
      try {
        if (this.billing && workspace.execution_target === 'cloud' && command.action.type === 'mode.set' && command.action.mode !== 'off')
          await this.billing.requireUsage(client, userId);
        const mutation = applyCloudCommand(workspace.snapshot, command);
        if (mutation.job && this.billing) await this.billing.requireUsage(client, userId);
        if (
          command.action.type === 'task.delete' ||
          command.action.type === 'chat.archive' ||
          (command.action.type === 'task.update' &&
            command.action.patch.status === 'done')
        ) {
          const stoppedThreads = workspace.snapshot.threads.filter(
            (thread) =>
              thread.archivedAt ||
              workspace.snapshot.tasks.some(
                (task) => task.id === thread.taskId && task.status === 'done'
              )
          );
          await client.query(
            "UPDATE cloud_jobs SET state = 'canceled' WHERE workspace_id = $1 AND thread_id IN (SELECT value FROM json_each($2)) AND state IN ('queued', 'running', 'blocked')",
            [workspace.id, stoppedThreads.map((thread) => thread.id)]
          );
          for (const thread of stoppedThreads) {
            thread.status = 'ready';
            thread.activity = null;
            thread.question = null;
            for (const message of thread.messages)
              if (message.status === 'pending') message.status = 'complete';
          }
        }
        if (mutation.job)
          await this.insertJob(client, workspace.id, mutation.job);
        if (mutation.stopRunId)
          await client.query(
            "UPDATE cloud_jobs SET state = 'canceled' WHERE id = $1 AND workspace_id = $2",
            [mutation.stopRunId, workspace.id]
          );
        let file: CompanionReceipt['file'];
        if (command.action.type === 'artifact.read') {
          const action = command.action;
          const result = workspace.snapshot.results.find(
            (item) => item.id === action.resultId
          );
          if (!result) throw new CloudError(404, 'Result not found.');
          const artifactId = result.artifacts[action.index]?.cloudArtifactId;
          const { rows } = await client.query<{
            file: NonNullable<CompanionReceipt['file']>;
          }>(
            'SELECT file FROM cloud_artifacts WHERE workspace_id = $1 AND id = $2',
            [workspace.id, artifactId ?? null]
          );
          if (!rows[0])
            throw new CloudError(
              404,
              'This file isn’t available on your phone.'
            );
          file = rows[0].file;
        }
        await this.save(client, workspace);
        receipt = {
          id: command.id,
          status: 'completed',
          error: null,
          taskVersions: Object.fromEntries(
            workspace.snapshot.tasks
              .filter((task) => before.get(task.id) !== task.updatedAt)
              .map((task) => [
                task.id,
                { before: before.get(task.id) ?? null, after: task.updatedAt }
              ])
          ),
          ...(file ? { file } : {})
        };
      } catch (error) {
        if (!(error instanceof CloudError)) throw error;
        workspace.snapshot = backup;
        receipt = {
          id: command.id,
          status: error.status === 409 ? 'conflict' : 'failed',
          error: error.message
        };
      }
      await client.query(
        'INSERT INTO cloud_receipts(workspace_id, id, receipt) VALUES ($1,$2,$3)',
        [workspace.id, command.id, JSON.stringify(receipt)]
      );
      return receipt;
    });
  }

  async exchange(userId: string, exchange: CloudExchange) {
    return this.transaction(async (client) => {
      const workspace = await this.workspace(client, userId, true);
      if (!this.billing) this.requirePro(workspace);
      const desktop = await client.query<{
        workspace_id: string; last_exchange_id: string | null;
        last_exchange_reply: { snapshot: CloudSnapshot; conflicts: string[] } | null;
      }>('SELECT * FROM cloud_desktops WHERE id = $1', [exchange.desktopId]);
      if (desktop.rows[0] && desktop.rows[0].workspace_id !== workspace.id)
        throw new CloudError(403, 'This computer belongs to a different Dony account.');
      if (desktop.rows[0]?.last_exchange_id === exchange.id)
        return desktop.rows[0].last_exchange_reply!;
      await client.query(
        `INSERT INTO cloud_desktops(id, workspace_id, name) VALUES ($1,$2,$3)
         ON CONFLICT(id) DO UPDATE SET name = excluded.name, last_seen_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`,
        [exchange.desktopId, workspace.id, exchange.name]
      );
      const before = JSON.stringify(workspace.snapshot);
      const base = exchange.base ?? emptyCloudSnapshot();
      // The new account starts Off even when the imported desktop was Proactive.
      if (!exchange.base) exchange.snapshot.mode = workspace.snapshot.mode;
      const merged = mergeCloudSnapshot(
        workspace.snapshot,
        base,
        exchange.snapshot
      );
      workspace.snapshot = merged.snapshot;
      if (JSON.stringify(workspace.snapshot) !== before)
        await this.save(client, workspace);
      const result = { ...merged, executionTarget: workspace.execution_target };
      await client.query(
        'UPDATE cloud_desktops SET last_exchange_id = $2, last_exchange_reply = $3 WHERE id = $1',
        [exchange.desktopId, exchange.id, JSON.stringify(result)]
      );
      return result;
    });
  }

  async edit(userId: string, change: (snapshot: CloudSnapshot) => void) {
    return this.transaction(async (client) => {
      const workspace = await this.workspace(client, userId, true);
      if (!this.billing) this.requirePro(workspace);
      change(workspace.snapshot);
      await this.save(client, workspace);
    });
  }

  async claim(): Promise<CloudJob | null> {
    return this.transaction(async (client) => {
      // A lost lease may have performed an external action. Never replay it blindly.
      const expired = await client.query<CloudJob>(
        "SELECT * FROM cloud_jobs WHERE state = 'running' AND lease_until < strftime('%Y-%m-%dT%H:%M:%fZ', 'now')",
        []
      );
      for (const job of expired.rows) {
        await client.query("UPDATE cloud_jobs SET state = 'failed', error = $2 WHERE id = $1", [job.id, 'Dony restarted during this run. Review the last activity before retrying.']);
        await this.finishInTransaction(
          client,
          job,
          'failed',
          'Dony restarted during this run. Review the last activity before retrying.'
        );
      }
      const { rows } = await client.query<CloudJob>(
        `
        SELECT j.*, w.user_id FROM cloud_jobs j JOIN cloud_workspaces w ON w.id = j.workspace_id
        WHERE j.state = 'queued' AND w.pro = true ORDER BY j.created_at LIMIT 1`,
        []
      );
      const job = rows[0];
      if (!job) return null;
      job.lease = randomUUID();
      job.state = 'running';
      await client.query(
        "UPDATE cloud_jobs SET state = 'running', lease = $2, lease_until = strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+90 seconds') WHERE id = $1",
        [job.id, job.lease]
      );
      return job;
    });
  }

  async heartbeat(job: CloudJob): Promise<boolean> {
    const { rows } = await this.pool.query(
      "UPDATE cloud_jobs SET lease_until = strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+90 seconds') WHERE id = $1 AND lease = $2 AND state = 'running' RETURNING id",
      [job.id, job.lease]
    );
    return rows.length > 0;
  }

  async checkpoint(job: CloudJob, messages: ModelMessage[]) {
    const { rows } = await this.pool.query(
      "UPDATE cloud_jobs SET messages = $3, step = step + 1 WHERE id = $1 AND lease = $2 AND state = 'running' RETURNING id",
      [job.id, job.lease, JSON.stringify(messages)]
    );
    if (!rows.length) throw new CloudError(409, 'This run was stopped.');
    job.messages = messages;
    job.step += 1;
  }

  private async workspaceById(client: D1Transaction, id: string): Promise<CloudWorkspaceRow | undefined> {
    let cache = this.transactionWorkspaces.get(client);
    if (!cache) {
      cache = new Map();
      this.transactionWorkspaces.set(client, cache);
    }
    const cached = cache.get(id);
    if (cached) return cached;
    const { rows } = await client.query<CloudWorkspaceRow>('SELECT * FROM cloud_workspaces WHERE id = $1', [id]);
    if (rows[0]) cache.set(id, this.rememberPlanning(rows[0]));
    return rows[0];
  }

  async activity(job: CloudJob, text: string, content?: string) {
    await this.transaction(async (client) => {
      const workspace = await this.workspaceById(client, job.workspace_id);
      if (!workspace) return;
      const thread = workspace.snapshot.threads.find(
        (item) =>
          item.id === job.thread_id && item.runId === job.id && !item.archivedAt
      );
      if (!workspace.pro || !thread || thread.status !== 'running') return;
      thread.activity = text;
      const message = thread.messages.find(
        (item) => item.id === job.assistant_message_id
      );
      if (message && content !== undefined) {
        message.content = content;
        message.updatedAt = cloudNow();
      }
      await this.save(client, workspace);
    });
  }

  async finishInTransaction(
    client: D1Transaction,
    job: CloudJob,
    state: 'completed' | 'blocked' | 'failed',
    text: string
  ) {
    const workspace = await this.workspaceById(client, job.workspace_id);
    if (!workspace) return;
    if (job.kind === 'plan') {
      const task = workspace.snapshot.tasks.find(
        (item) => item.id === job.thread_id
      );
      if (task) {
        task.proactivePlanningStatus = 'failed';
        task.updatedAt = cloudNow();
        await this.save(client, workspace);
      }
      return;
    }
    const thread = workspace.snapshot.threads.find(
      (item) => item.id === job.thread_id && item.runId === job.id
    );
    if (!thread || !workspace.pro || thread.archivedAt) return;
    const now = cloudNow();
    const message = thread.messages.find(
      (item) => item.id === job.assistant_message_id
    );
    if (message)
      Object.assign(message, {
        content: text || message.content,
        status: state === 'failed' ? 'error' : 'complete',
        updatedAt: now
      });
    thread.status =
      state === 'blocked' ? 'blocked' : state === 'failed' ? 'failed' : 'ready';
    thread.activity = null;
    thread.updatedAt = now;
    const task = workspace.snapshot.tasks.find(
      (item) => item.id === thread.taskId
    );
    if (task) {
      task.proactiveExecutionStatus = state === 'failed' ? 'failed' : 'blocked';
      task.updatedAt = now;
      if (state === 'completed') {
        const agent = workspace.snapshot.agents.find(
          (item) => item.id === thread.agentId
        )!;
        const artifacts = await client.query<{
          id: string;
          file: { name: string };
        }>(
          'SELECT id, file FROM cloud_artifacts WHERE workspace_id = $1 AND thread_id = $2 ORDER BY id',
          [workspace.id, thread.id]
        );
        workspace.snapshot.results.push({
          id: job.id,
          taskId: task.id,
          runId: job.id,
          threadId: thread.id,
          agentId: agent.id,
          assistantMessageId: job.assistant_message_id,
          taskTitle: task.title,
          agentName: agent.name,
          agentEmoji: agent.emoji,
          agentColor: agent.color,
          providerLabel: 'Dony',
          threadTitle: thread.title,
          preview: text,
          outcome: 'review',
          artifacts: artifacts.rows.map((item) => ({
            name: item.file.name,
            type: 'file' as const,
            cloudArtifactId: item.id
          })),
          completedAt: now,
          dismissedAt: null,
          createdAt: now,
          updatedAt: now
        });
      }
    }
    await this.save(client, workspace);
    await client.query(
      'INSERT INTO cloud_notifications(id, workspace_id, thread_id, title, body) VALUES ($1,$2,$3,$4,$5)',
      [
        randomUUID(),
        workspace.id,
        thread.id,
        state === 'blocked'
          ? 'Dony needs your answer'
          : state === 'failed'
            ? 'A Dony task needs attention'
            : 'Dony finished working',
        thread.title
      ]
    );
  }

  async finish(
    job: CloudJob,
    state: 'completed' | 'blocked' | 'failed',
    text: string
  ) {
    await this.transaction(async (client) => {
      const { rows } = await client.query(
        "SELECT id FROM cloud_jobs WHERE id = $1 AND lease = $2 AND state = 'running'",
        [job.id, job.lease]
      );
      if (!rows.length) return;
      await client.query('UPDATE cloud_jobs SET state = $2 WHERE id = $1', [job.id, state]);
      await this.finishInTransaction(client, job, state, text);
    });
  }

  async createOnboardingJob(userId: string): Promise<CloudJob> {
    const workspace = await this.workspace(this.pool, userId);
    const id = randomUUID();
    const threadId = randomUUID();
    const messageId = randomUUID();
    // Inline read-only generation uses normal budget accounting without creating a chat.
    // Blocked keeps the background worker from claiming this request.
    await this.pool.query(
      "INSERT INTO cloud_jobs(id, workspace_id, thread_id, assistant_message_id, kind, state) VALUES ($1,$2,$3,$4,'onboarding','blocked')",
      [id, workspace.id, threadId, messageId]
    );
    return { id, workspace_id: workspace.id, user_id: userId, thread_id: threadId,
      assistant_message_id: messageId, kind: 'onboarding', state: 'blocked',
      messages: [], files: [], lease: null, step: 0 };
  }

  async reserve(job: CloudJob, dollars: number): Promise<string> {
    if (!Number.isFinite(dollars) || dollars <= 0)
      throw new CloudError(
        503,
        'Dony cannot start right now. Please try again in a few minutes.'
      );
    if (this.billing) {
      return this.transaction(async (client) => {
        const id = randomUUID();
        const micros = Math.ceil(dollars * 1_000_000);
        await this.billing!.reserve(client, job.user_id, job.id, id, micros);
        await client.query('INSERT INTO cloud_spend(id, job_id, reserved_micros) VALUES ($1,$2,$3)', [id, job.id, micros]);
        return id;
      });
    }
    if (dollars > cloudDailyLimitUsd)
      throw new CloudError(
        429,
        'This task is too large to start all at once. Please try a smaller request or fewer attachments.'
      );
    return this.transaction(async (client) => {
      const { rows } = await client.query<{ spent: string }>(
        "SELECT COALESCE(SUM(COALESCE(charged_micros, reserved_micros)), 0) AS spent FROM cloud_spend WHERE day = date('now')",
        []
      );
      const micros = Math.ceil(dollars * 1_000_000);
      if (Number(rows[0]!.spent) + micros > cloudDailyLimitUsd * 1_000_000) {
        const reset = new Date();
        reset.setUTCHours(24, 0, 0, 0);
        const hours = Math.max(
          1,
          Math.ceil((reset.getTime() - Date.now()) / 3_600_000)
        );
        throw new CloudError(
          429,
          `Dony can’t start this task within today’s usage limit. Please try again in about ${hours} ${hours === 1 ? 'hour' : 'hours'}. Your task is still saved.`
        );
      }
      const id = randomUUID();
      await client.query(
        'INSERT INTO cloud_spend(id, job_id, reserved_micros) VALUES ($1,$2,$3)',
        [id, job.id, micros]
      );
      return id;
    });
  }

  async settle(
    id: string,
    dollars: number | undefined,
    status: 'settled' | 'rejected' = 'settled'
  ) {
    // Unknown costs keep their hold until the provider supplies billing evidence.
    if (dollars === undefined || !Number.isFinite(dollars) || dollars < 0)
      return;
    await this.transaction(async (client) => {
      await this.billing?.settle(client, id, Math.ceil(dollars * 1_000_000));
      await client.query(
        'UPDATE cloud_spend SET charged_micros = $2, cost_status = $3 WHERE id = $1 AND charged_micros IS NULL',
        [id, Math.ceil(dollars * 1_000_000), status]
      );
    });
  }

  async recordGeneration(id: string, generationId: string) {
    await this.pool.query(
      'UPDATE cloud_spend SET generation_id = $2 WHERE id = $1',
      [id, generationId]
    );
  }

  async markUnknownCost(id: string) {
    await this.pool.query(
      "UPDATE cloud_spend SET cost_status = 'unknown' WHERE id = $1 AND charged_micros IS NULL",
      [id]
    );
  }

  async costsToReconcile() {
    const { rows } = await this.pool.query<{
      id: string;
      generation_id: string;
    }>(
      `
      UPDATE cloud_spend SET checked_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id IN (
        SELECT id FROM cloud_spend
        WHERE charged_micros IS NULL AND generation_id IS NOT NULL
          AND (cost_status = 'unknown' OR created_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-15 minutes'))
          AND (checked_at IS NULL OR checked_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-5 minutes'))
        ORDER BY checked_at NULLS FIRST, created_at LIMIT 10
      ) RETURNING id, generation_id
    `,
      []
    );
    return rows;
  }

  async tool<T>(
    job: CloudJob,
    id: string,
    execute: () => Promise<T>
  ): Promise<T> {
    const inserted = await this.pool.query(
      "INSERT INTO cloud_tool_calls(job_id, id, state) VALUES ($1,$2,'started') ON CONFLICT DO NOTHING RETURNING id",
      [job.id, id]
    );
    if (!inserted.rows.length) {
      const { rows } = await this.pool.query<{ state: string; result: T }>(
        'SELECT state, result FROM cloud_tool_calls WHERE job_id = $1 AND id = $2',
        [job.id, id]
      );
      if (rows[0]?.state === 'completed') return rows[0].result;
      throw new CloudError(
        409,
        'This tool may already have run. Review the result before retrying.'
      );
    }
    const result = await execute();
    await this.pool.query(
      "UPDATE cloud_tool_calls SET state = 'completed', result = $3 WHERE job_id = $1 AND id = $2",
      [job.id, id, JSON.stringify(result)]
    );
    return result;
  }
}
