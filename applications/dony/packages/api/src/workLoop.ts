// A wake-up is only a hint: callers persist work before sending it. Coalesce
// bursts, remember wakes while busy, and drain batches without concurrent runs.
export class WorkLoop {
  private stopped = true;
  private running = false;
  private pending = false;

  constructor(private readonly tick: () => Promise<boolean>) {}

  start() {
    if (!this.stopped) return;
    this.stopped = false;
    this.wake();
  }

  stop() {
    this.stopped = true;
    this.pending = false;
  }

  wake() {
    if (this.stopped) return;
    this.pending = true;
    if (!this.running) void this.drain();
  }

  private async drain() {
    this.running = true;
    try {
      while (!this.stopped && this.pending) {
        this.pending = false;
        if (await this.tick()) this.pending = true;
      }
    } catch {
      // Durable work remains available to the recovery scheduler.
      console.error('Background work will retry on recovery.');
    } finally {
      this.running = false;
    }
  }
}
