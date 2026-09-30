import { describe, expect, it, vi } from 'vitest';

import { initializeDatabase } from '../src/database';
import { D1QuotaExceededError, remoteD1 } from '../src/d1/client';

describe('initializeDatabase', () => {
  it('recognizes Cloudflare quota responses before parsing JSON', async () => {
    const send = remoteD1({ url: 'https://database.test', token: 'test' },
      vi.fn().mockResolvedValue(new Response('error code: 1027', { status: 429 })));
    await expect(send([{ sql: 'SELECT 1' }])).rejects.toBeInstanceOf(D1QuotaExceededError);
  });

  it('waits after quota exhaustion and resumes all startup work once available', async () => {
    const migrateAuth = vi.fn().mockRejectedValueOnce(new Error('Database adapter failed', {
      cause: new D1QuotaExceededError()
    })).mockResolvedValue(undefined);
    const migrateLocalToolResults = vi.fn();
    const cleanupLocalToolResults = vi.fn();
    const waitForQuotaReset = vi.fn(async () => {
      expect(migrateAuth).toHaveBeenCalledTimes(1);
      expect(migrateLocalToolResults).not.toHaveBeenCalled();
    });
    await initializeDatabase({ allowUnavailable: false, migrateAuth, migrateLocalToolResults,
      cleanupLocalToolResults, waitForQuotaReset, warn: vi.fn() });
    expect(waitForQuotaReset).toHaveBeenCalledOnce();
    expect(migrateAuth).toHaveBeenCalledTimes(2);
    expect(migrateLocalToolResults).toHaveBeenCalledOnce();
    expect(cleanupLocalToolResults).toHaveBeenCalledOnce();
  });
  it('runs all database startup work', async () => {
    const migrateAuth = vi.fn().mockResolvedValue(undefined);
    const migrateLocalToolResults = vi.fn().mockResolvedValue(undefined);
    const cleanupLocalToolResults = vi.fn().mockResolvedValue(undefined);

    await initializeDatabase({
      allowUnavailable: false,
      migrateAuth,
      migrateLocalToolResults,
      cleanupLocalToolResults
    });

    expect(migrateAuth).toHaveBeenCalledOnce();
    expect(migrateLocalToolResults).toHaveBeenCalledOnce();
    expect(cleanupLocalToolResults).toHaveBeenCalledOnce();
  });

  it('allows local development to start when the database is unavailable', async () => {
    const error = Object.assign(new Error('connection timed out'), {
      code: 'ETIMEDOUT'
    });
    const warn = vi.fn();

    await expect(
      initializeDatabase({
        allowUnavailable: true,
        migrateAuth: vi.fn().mockRejectedValue(error),
        migrateLocalToolResults: vi.fn(),
        cleanupLocalToolResults: vi.fn(),
        warn
      })
    ).resolves.toBeUndefined();

    expect(warn).toHaveBeenCalledWith(
      'Dony API database is unavailable in development (ETIMEDOUT). ' +
        'Starting without database-backed auth and local tool results.'
    );
  });

  it('keeps database startup strict outside local development', async () => {
    const error = new Error('connection failed');

    await expect(
      initializeDatabase({
        allowUnavailable: false,
        migrateAuth: vi.fn().mockRejectedValue(error),
        migrateLocalToolResults: vi.fn(),
        cleanupLocalToolResults: vi.fn()
      })
    ).rejects.toBe(error);
  });
});
