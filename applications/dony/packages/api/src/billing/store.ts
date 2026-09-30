import { randomUUID } from 'node:crypto';
import type { BillingStatus } from '@dony/domain';
import type { DonyDatabase, D1Transaction, QueryClient } from '../database';
import { CloudError } from '../cloudCommands';
import { billingProducts, planAllowance, usageWindow } from './catalog';

export type VerifiedPurchase = {
  id: string;
  accountToken: string;
  originalId: string;
  productId: string;
  purchasedAt: number;
  expiresAt: number | null;
  signedAt: number;
  revokedAt: number | null;
  upgraded: boolean;
};
type PurchaseRow = {
  id: string;
  product_id: string;
  purchased_ms: number;
  expires_ms: number | null;
  signed_ms: number;
  revoked_ms: number | null;
  upgraded: number;
};
type Allocation = {
  account_id: string;
  period_id: string | null;
  allowance_micros: number;
  extra_micros: number;
  settled: number;
};

export class BillingStore {
  constructor(
    readonly pool: DonyDatabase,
    readonly configured: boolean,
    private readonly now = Date.now,
    private readonly sandboxUsers: Set<string> | null = null
  ) {}

  async migrate() {
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS billing_accounts (
        id TEXT PRIMARY KEY, user_id TEXT UNIQUE
      );
      CREATE TABLE IF NOT EXISTS billing_purchases (
        id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES billing_accounts(id),
        original_id TEXT NOT NULL, product_id TEXT NOT NULL, kind TEXT NOT NULL,
        purchased_ms INTEGER NOT NULL, expires_ms INTEGER, signed_ms INTEGER NOT NULL,
        revoked_ms INTEGER, upgraded INTEGER NOT NULL DEFAULT 0, extra_micros INTEGER NOT NULL DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS billing_purchases_account ON billing_purchases(account_id, purchased_ms);
      CREATE TABLE IF NOT EXISTS billing_allocations (
        spend_id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES billing_accounts(id),
        job_id TEXT NOT NULL, period_id TEXT,
        allowance_micros INTEGER NOT NULL, extra_micros INTEGER NOT NULL,
        settled INTEGER NOT NULL DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS billing_allocations_account ON billing_allocations(account_id, period_id);
      CREATE TABLE IF NOT EXISTS billing_refresh (
        account_id TEXT PRIMARY KEY REFERENCES billing_accounts(id), next_ms INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS billing_refresh_due ON billing_refresh(next_ms);
    `);
    await this.pool.trackTables([
      'billing_accounts',
      'billing_purchases',
      'billing_allocations',
      'billing_refresh'
    ]);
  }

  async account(userId: string): Promise<string> {
    await this.pool.query(
      'INSERT OR IGNORE INTO billing_accounts(id, user_id) VALUES ($1,$2)',
      [randomUUID(), userId]
    );
    const { rows } = await this.pool.query<{ id: string }>(
      'SELECT id FROM billing_accounts WHERE user_id = $1',
      [userId]
    );
    return rows[0]!.id;
  }

  async read(client: QueryClient, userId: string) {
    const account = await client.query<{ id: string }>(
      'SELECT id FROM billing_accounts WHERE user_id = $1',
      [userId]
    );
    const accountId = account.rows[0]?.id ?? '';
    const purchases = await client.query<PurchaseRow>(
      "SELECT * FROM billing_purchases WHERE account_id = $1 AND kind = 'subscription' ORDER BY purchased_ms DESC, signed_ms DESC LIMIT 1",
      [accountId]
    );
    const latest = purchases.rows[0];
    const product = latest ? billingProducts[latest.product_id] : undefined;
    const now = this.now();
    const active =
      latest &&
      product?.kind === 'subscription' &&
      !latest.revoked_ms &&
      !latest.upgraded &&
      latest.purchased_ms <= now &&
      latest.expires_ms! > now
        ? { purchase: latest, product }
        : null;
    const window = active
      ? usageWindow(
          active.purchase.purchased_ms,
          active.purchase.expires_ms!,
          now,
          active.product.period
        )
      : null;
    const periodId =
      active && window ? `${active.purchase.id}:${window.index}` : null;
    const allowance = active ? planAllowance[active.product.plan] : 0;
    const granted = await client.query<{ amount: number }>(
      'SELECT COALESCE(SUM(extra_micros), 0) AS amount FROM billing_purchases WHERE account_id = $1 AND revoked_ms IS NULL',
      [accountId]
    );
    const used = await client.query<{ allowance: number; extra: number }>(
      `SELECT COALESCE(SUM(CASE WHEN period_id = $2 THEN allowance_micros ELSE 0 END), 0) AS allowance,
       COALESCE(SUM(extra_micros), 0) AS extra FROM billing_allocations WHERE account_id = $1`,
      [accountId, periodId]
    );
    const monthlyUsed = Number(used.rows[0]!.allowance);
    const extraRemaining = Math.max(
      0,
      Number(granted.rows[0]!.amount) - Number(used.rows[0]!.extra)
    );
    const remaining = Math.max(0, allowance - monthlyUsed) + extraRemaining;
    return {
      accountId,
      active,
      window,
      periodId,
      allowance,
      monthlyUsed,
      extraRemaining,
      remaining
    };
  }

  async status(userId: string): Promise<BillingStatus> {
    await this.account(userId);
    return this.publicStatus(await this.read(this.pool, userId));
  }

  publicStatus(
    state: Awaited<ReturnType<BillingStore['read']>>
  ): BillingStatus {
    const reference = state.allowance || planAllowance.pro;
    return {
      accountToken: state.accountId,
      configured: this.configured,
      plan: state.active?.product.plan ?? null,
      period: state.active?.product.period ?? null,
      monthlyUsedPercent: state.allowance
        ? Math.min(100, (state.monthlyUsed / state.allowance) * 100)
        : 0,
      extraRemainingPercent: (state.extraRemaining / reference) * 100,
      resetsAt: state.allowance && state.window ? new Date(state.window.end).toISOString() : null,
      expiresAt: state.active
        ? new Date(state.active.purchase.expires_ms!).toISOString()
        : null,
      canRunCloud: state.remaining > 0,
      canUseRemoteDesktop: Boolean(state.active),
      limitReached: state.allowance > 0 && state.remaining <= 0
    };
  }

  // Only call with an Apple-verified transaction. Never accept a client plan or amount.
  async apply(purchase: VerifiedPurchase, userId?: string) {
    const product = billingProducts[purchase.productId];
    if (!product)
      throw new CloudError(400, 'This purchase is not a Dony product.');
    await this.pool.transaction(async (client) => {
      const account = await client.query<{ user_id: string | null }>(
        'SELECT user_id FROM billing_accounts WHERE id = $1',
        [purchase.accountToken]
      );
      const owner = account.rows[0]?.user_id;
      // A deleted Dony account stays tombstoned so purchases cannot be claimed again.
      if (account.rows[0] && owner === null && userId === undefined) return;
      if (!owner || (userId !== undefined && owner !== userId))
        throw new CloudError(
          403,
          'This purchase belongs to another Dony account. Sign in to that account to restore it.'
        );
      if (
        purchase.id.startsWith('Sandbox:') &&
        this.sandboxUsers &&
        !this.sandboxUsers.has(owner)
      )
        throw new CloudError(
          403,
          'Sandbox purchases are enabled only for Dony test accounts.'
        );
      const previous = await client.query<PurchaseRow & { account_id: string }>(
        'SELECT * FROM billing_purchases WHERE id = $1',
        [purchase.id]
      );
      const saved = previous.rows[0];
      if (saved && saved.account_id !== purchase.accountToken)
        throw new CloudError(403, 'This purchase belongs to another account.');
      // Restore/replay must not undo a refund or replace a newer store event.
      if (saved && saved.signed_ms >= purchase.signedAt) return;
      await client.query(
        `INSERT INTO billing_purchases
        (id, account_id, original_id, product_id, kind, purchased_ms, expires_ms, signed_ms, revoked_ms, upgraded, extra_micros)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
        ON CONFLICT(id) DO UPDATE SET expires_ms = excluded.expires_ms, signed_ms = excluded.signed_ms,
          revoked_ms = excluded.revoked_ms, upgraded = excluded.upgraded`,
        [
          purchase.id,
          purchase.accountToken,
          purchase.originalId,
          purchase.productId,
          product.kind,
          purchase.purchasedAt,
          purchase.expiresAt,
          purchase.signedAt,
          purchase.revokedAt,
          purchase.upgraded,
          product.kind === 'addon' ? product.micros : 0
        ]
      );
      // Wake planning after commit. reserve() still verifies current account access.
      await client.query(
        `INSERT OR IGNORE INTO cloud_planning_pending(workspace_id)
        SELECT id FROM cloud_workspaces WHERE user_id = $1`,
        [owner]
      );
      // Re-read the committed purchase on the next worker cycle. This also
      // schedules monthly refreshes for annual plans, which have no renewal event.
      await client.query(
        `INSERT INTO billing_refresh(account_id, next_ms) VALUES ($1, $2)
         ON CONFLICT(account_id) DO UPDATE SET next_ms = excluded.next_ms`,
        [purchase.accountToken, this.now()]
      );
    });
  }

  async refreshPeriods() {
    return this.pool.transaction(async (client) => {
      const { rows } = await client.query<{
        account_id: string;
        user_id: string | null;
      }>(
        `SELECT r.account_id, a.user_id FROM billing_refresh r
         JOIN billing_accounts a ON a.id = r.account_id
         WHERE r.next_ms <= $1 ORDER BY r.next_ms LIMIT 20`,
        [this.now()]
      );
      for (const row of rows) {
        const state = row.user_id ? await this.read(client, row.user_id) : null;
        if (state?.window) {
          await client.query(
            'UPDATE billing_refresh SET next_ms = $2 WHERE account_id = $1',
            [row.account_id, state.window.end]
          );
        } else {
          await client.query(
            'DELETE FROM billing_refresh WHERE account_id = $1',
            [row.account_id]
          );
        }
        if (state?.remaining) {
          await client.query(
            `INSERT OR IGNORE INTO cloud_planning_pending(workspace_id)
             SELECT id FROM cloud_workspaces WHERE user_id = $1`,
            [row.user_id]
          );
        }
      }
      return rows.length === 20;
    });
  }

  async requireUsage(client: QueryClient, userId: string) {
    const state = await this.read(client, userId);
    if (state.remaining > 0) return state;
    if (!state.active || state.active.product.plan === 'connect')
      throw new CloudError(403, 'Choose a plan or connect your Mac to use AI.');
    throw new CloudError(
      429,
      'You’ve used this month’s AI allowance. Add extra usage, upgrade your plan, or connect your Mac.'
    );
  }

  async reserve(
    client: D1Transaction,
    userId: string,
    jobId: string,
    spendId: string,
    micros: number
  ) {
    const state = await this.requireUsage(client, userId);
    if (micros > state.remaining)
      throw new CloudError(
        429,
        'This task needs more than your remaining AI allowance. Add extra usage or try a smaller task.'
      );
    const monthly = Math.min(
      micros,
      Math.max(0, state.allowance - state.monthlyUsed)
    );
    await client.query(
      `INSERT INTO billing_allocations(spend_id, account_id, job_id, period_id, allowance_micros, extra_micros)
      VALUES ($1,$2,$3,$4,$5,$6)`,
      [
        spendId,
        state.accountId,
        jobId,
        state.periodId,
        monthly,
        micros - monthly
      ]
    );
  }

  async settle(client: D1Transaction, spendId: string, micros: number) {
    const result = await client.query<Allocation>(
      'SELECT * FROM billing_allocations WHERE spend_id = $1',
      [spendId]
    );
    const allocation = result.rows[0];
    if (!allocation || allocation.settled) return;
    const account = await client.query<{ user_id: string | null }>(
      'SELECT user_id FROM billing_accounts WHERE id = $1',
      [allocation.account_id]
    );
    const userId = account.rows[0]?.user_id;
    const state = userId ? await this.read(client, userId) : null;
    // Other requests may have released their holds. Use that month's available
    // allowance before charging extras, but never borrow from a new period.
    const available =
      state?.periodId === allocation.period_id
        ? Math.max(
            0,
            state!.allowance - state!.monthlyUsed + allocation.allowance_micros
          )
        : allocation.allowance_micros;
    const monthly = Math.min(micros, available);
    await client.query(
      'UPDATE billing_allocations SET allowance_micros = $2, extra_micros = $3, settled = 1 WHERE spend_id = $1',
      [spendId, monthly, micros - monthly]
    );
  }
}
