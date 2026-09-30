import type { DonyDatabase } from './database';

export const CLOUD_RECOVERY_INTERVAL_MS = 5 * 60_000;

// Each instance makes one small election request per interval. Only the winner
// wakes consumers for the account-wide recovery scan; normal local wakes don't
// need this lease. Use database time to avoid clock skew between instances.
export class CloudRecovery {
  private timer: ReturnType<typeof setInterval> | undefined;
  private busy = false;

  constructor(private readonly pool: DonyDatabase, private readonly wake: () => void) {}

  start() {
    if (this.timer) return;
    this.timer = setInterval(() => void this.check(), CLOUD_RECOVERY_INTERVAL_MS);
    this.timer.unref();
  }

  stop() {
    clearInterval(this.timer);
    this.timer = undefined;
  }

  async check() {
    if (this.busy) return;
    this.busy = true;
    try {
      const { rows } = await this.pool.query(
        `INSERT INTO cloud_recovery(id, next_check_at)
         VALUES ('background', CAST(strftime('%s', 'now') AS INTEGER) + 300)
         ON CONFLICT(id) DO UPDATE SET next_check_at = excluded.next_check_at
         WHERE cloud_recovery.next_check_at <= CAST(strftime('%s', 'now') AS INTEGER)
         RETURNING id`
      );
      if (rows.length) this.wake();
    } catch {
      console.error('Cloud recovery check will retry.');
    } finally {
      this.busy = false;
    }
  }
}
