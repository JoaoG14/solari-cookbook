import { randomUUID } from 'node:crypto';

export const SYNC_RECOVERY_MS = 5 * 60_000;

// Hints stay in the API process, never in D1. A timeout/restart forces clients
// to reconcile durable state, including writes made by another API instance.
export class WorkspaceChanges {
  private readonly epoch = randomUUID();
  private readonly versions = new Map<string, number>();
  private readonly listeners = new Map<string, Set<() => void>>();

  private cursor(userId: string) {
    return `${this.epoch}:${this.versions.get(userId) ?? 0}`;
  }

  publish(userId: string) {
    this.versions.set(userId, (this.versions.get(userId) ?? 0) + 1);
    for (const listener of this.listeners.get(userId) ?? []) listener();
  }

  async wait(userId: string, cursor: string | undefined, signal: AbortSignal) {
    if (cursor !== this.cursor(userId) || signal.aborted)
      return { cursor: this.cursor(userId) };
    return new Promise<{ cursor: string }>((resolve) => {
      const listeners = this.listeners.get(userId) ?? new Set<() => void>();
      this.listeners.set(userId, listeners);
      const finish = () => {
        clearTimeout(timer);
        signal.removeEventListener('abort', finish);
        listeners.delete(finish);
        if (!listeners.size) this.listeners.delete(userId);
        resolve({ cursor: this.cursor(userId) });
      };
      const timer = setTimeout(finish, SYNC_RECOVERY_MS);
      listeners.add(finish);
      signal.addEventListener('abort', finish, { once: true });
    });
  }
}
