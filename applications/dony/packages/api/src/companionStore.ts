import { isDeepStrictEqual } from 'node:util';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import type { BillingStore } from './billing/store';
import type { D1Transaction, DonyDatabase } from './database';
import type {
  CompanionCommand,
  CompanionReceipt,
  CompanionSnapshot
} from '@dony/domain';

const hash = (value: string): string =>
  createHash('sha256').update(value).digest('hex');
const iso = (value: Date): string => value.toISOString();
export class CompanionError extends Error {
  constructor(
    public status: 401 | 403 | 404 | 409 | 410,
    message: string
  ) {
    super(message);
  }
}
type DesktopRow = {
  id: string;
  user_id: string;
  name: string;
  revision: number;
  snapshot: CompanionSnapshot | null;
  last_seen_at: Date | null;
};
type DeviceRow = {
  id: string;
  desktop_id: string;
  name: string;
  created_at: Date;
  revoked_at: Date | null;
};

export class CompanionStore {
  constructor(private readonly pool: DonyDatabase, private readonly billing?: BillingStore) {}

  async migrate(): Promise<void> {
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS companion_desktops (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL, name TEXT NOT NULL,
        snapshot TEXT, revision INTEGER NOT NULL DEFAULT 0, last_seen_at TEXT
      );
      CREATE INDEX IF NOT EXISTS companion_desktops_user ON companion_desktops(user_id);
      CREATE TABLE IF NOT EXISTS companion_pairings (
        code_hash TEXT PRIMARY KEY, desktop_id TEXT NOT NULL REFERENCES companion_desktops(id) ON DELETE CASCADE,
        expires_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS companion_devices (
        id TEXT PRIMARY KEY, desktop_id TEXT NOT NULL REFERENCES companion_desktops(id) ON DELETE CASCADE,
        name TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')), revoked_at TEXT
      );
      CREATE TABLE IF NOT EXISTS companion_commands (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
        desktop_id TEXT NOT NULL REFERENCES companion_desktops(id) ON DELETE CASCADE,
        device_id TEXT NOT NULL REFERENCES companion_devices(id) ON DELETE CASCADE,
        action TEXT NOT NULL, receipt TEXT, created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
      );
      CREATE INDEX IF NOT EXISTS companion_commands_pending ON companion_commands(desktop_id, sequence) WHERE receipt IS NULL;
    `);
    await this.pool.trackTables(['companion_desktops', 'companion_pairings', 'companion_devices', 'companion_commands']);
  }

  private async transaction<T>(
    run: (client: D1Transaction) => Promise<T>
  ): Promise<T> {
    return this.pool.transaction(run);
  }

  async desktop(userId: string, desktopId: string): Promise<DesktopRow> {
    const { rows } = await this.pool.query<DesktopRow>(
      'SELECT * FROM companion_desktops WHERE id = $1 AND user_id = $2',
      [desktopId, userId]
    );
    if (!rows[0])
      throw new CompanionError(
        404,
        'This desktop is not connected to your account.'
      );
    return rows[0];
  }

  async register(userId: string, id: string, name: string): Promise<void> {
    await this.pool.query(
      'INSERT INTO companion_desktops (id, user_id, name) VALUES ($1, $2, $3) ON CONFLICT (id) DO NOTHING',
      [id, userId, name]
    );
    await this.desktop(userId, id);
  }

  async requireRemoteAccess(userId: string): Promise<void> {
    if (!this.billing) return;
    if ((await this.billing.status(userId)).canUseRemoteDesktop) return;
    throw new CompanionError(403, 'Connect from anywhere with Dony Connect, Pro, or Max.');
  }

  async requireDeviceAccess(device: DeviceRow): Promise<void> {
    const { rows } = await this.pool.query<{ user_id: string }>(
      'SELECT user_id FROM companion_desktops WHERE id = $1', [device.desktop_id]
    );
    if (!rows[0]) throw new CompanionError(401, 'This desktop was disconnected.');
    await this.requireRemoteAccess(rows[0].user_id);
  }

  // Mirror only credentials already issued by the Mac's local pairing flow.
  async syncDevices(userId: string, desktopId: string, devices: { id: string; name: string; tokenHash: string }[]) {
    await this.desktop(userId, desktopId);
    await this.transaction(async (client) => {
      for (const device of devices) {
        await client.query(
          `INSERT INTO companion_devices(id, desktop_id, name, token_hash) VALUES ($1,$2,$3,$4)
           ON CONFLICT(id) DO NOTHING`, [device.id, desktopId, device.name, device.tokenHash]
        );
      }
      await client.query(
        `UPDATE companion_devices SET revoked_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
         WHERE desktop_id = $1 AND revoked_at IS NULL AND id NOT IN (SELECT value FROM json_each($2))`,
        [desktopId, devices.map(device => device.id)]
      );
    });
  }

  async pairCode(
    userId: string,
    desktopId: string
  ): Promise<{ code: string; expiresAt: string }> {
    await this.desktop(userId, desktopId);
    const code = randomBytes(12).toString('hex').toUpperCase();
    const expiresAt = new Date(Date.now() + 5 * 60_000);
    await this.transaction(async (client) => {
      await client.query(
        `DELETE FROM companion_pairings WHERE desktop_id = $1 OR expires_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`,
        [desktopId]
      );
      await client.query(
        'INSERT INTO companion_pairings (code_hash, desktop_id, expires_at) VALUES ($1, $2, $3)',
        [hash(code), desktopId, expiresAt]
      );
    });
    return { code, expiresAt: iso(expiresAt) };
  }

  async pair(
    code: string,
    name: string
  ): Promise<{
    token: string;
    deviceId: string;
    desktopId: string;
    desktopName: string;
    accountId: string;
  }> {
    return this.transaction(async (client) => {
      const pairing = await client.query<{ desktop_id: string }>(
        `SELECT desktop_id FROM companion_pairings WHERE code_hash = $1 AND expires_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`,
        [hash(code.replace(/[\s-]/g, '').toUpperCase())]
      );
      const desktopId = pairing.rows[0]?.desktop_id;
      if (!desktopId)
        throw new CompanionError(
          410,
          'This pairing code has expired or was already used. Create a new code on your desktop.'
        );
      await client.query('DELETE FROM companion_pairings WHERE code_hash = $1', [hash(code.replace(/[\s-]/g, '').toUpperCase())]);
      const desktop = await client.query<DesktopRow>(
        'SELECT * FROM companion_desktops WHERE id = $1',
        [desktopId]
      );
      const token = randomBytes(32).toString('base64url');
      const deviceId = randomUUID();
      await client.query(
        'INSERT INTO companion_devices (id, desktop_id, name, token_hash) VALUES ($1, $2, $3, $4)',
        [deviceId, desktopId, name, hash(token)]
      );
      return {
        token,
        deviceId,
        desktopId,
        desktopName: desktop.rows[0]!.name,
        accountId: desktop.rows[0]!.user_id
      };
    });
  }

  async device(token: string): Promise<DeviceRow> {
    const { rows } = await this.pool.query<DeviceRow>(
      'SELECT * FROM companion_devices WHERE token_hash = $1 AND revoked_at IS NULL',
      [hash(token)]
    );
    if (!rows[0])
      throw new CompanionError(
        401,
        'This phone is disconnected. Link it again from your desktop.'
      );
    return rows[0];
  }

  async devices(userId: string, desktopId: string) {
    await this.desktop(userId, desktopId);
    const { rows } = await this.pool.query<DeviceRow>(
      'SELECT * FROM companion_devices WHERE desktop_id = $1 AND revoked_at IS NULL ORDER BY created_at',
      [desktopId]
    );
    return rows.map((row) => ({
      id: row.id,
      name: row.name,
      createdAt: iso(row.created_at)
    }));
  }

  async revoke(
    userId: string,
    desktopId: string,
    deviceId: string
  ): Promise<void> {
    await this.desktop(userId, desktopId);
    await this.revokeDevice(desktopId, deviceId);
  }

  async revokeDevice(desktopId: string, deviceId: string): Promise<void> {
    await this.transaction(async (client) => {
      await client.query(
        `UPDATE companion_devices SET revoked_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = $1 AND desktop_id = $2`,
        [deviceId, desktopId]
      );
      await client.query(
        `UPDATE companion_commands SET receipt = json_object('id', id, 'status', 'failed', 'error', 'Phone disconnected before this change reached the desktop.') WHERE device_id = $1 AND desktop_id = $2 AND receipt IS NULL`,
        [deviceId, desktopId]
      );
    });
  }

  async disconnect(userId: string, desktopId: string): Promise<void> {
    await this.desktop(userId, desktopId);
    await this.pool.query(
      'DELETE FROM companion_desktops WHERE id = $1 AND user_id = $2',
      [desktopId, userId]
    );
  }

  async submit(device: DeviceRow, command: CompanionCommand): Promise<void> {
    await this.requireDeviceAccess(device);
    await this.transaction(async (client) => {
      const active = await client.query(
        'SELECT id FROM companion_devices WHERE id = $1 AND revoked_at IS NULL',
        [device.id]
      );
      if (!active.rowCount)
        throw new CompanionError(401, 'This phone was disconnected.');
      const existing = await client.query<{ device_id: string; action: CompanionCommand['action'] }>(
        'SELECT device_id, action FROM companion_commands WHERE id = $1', [command.id]
      );
      if (existing.rows[0]) {
        if (existing.rows[0].device_id !== device.id || !isDeepStrictEqual(existing.rows[0].action, command.action))
          throw new CompanionError(409, 'This change ID was already used.');
        return;
      }
      await client.query(
        'INSERT INTO companion_commands (id, desktop_id, device_id, action) VALUES ($1, $2, $3, $4)',
        [command.id, device.desktop_id, device.id, command.action]
      );
    });
  }

  async exchange(
    userId: string,
    desktopId: string,
    snapshot: CompanionSnapshot | undefined,
    receipts: CompanionReceipt[]
  ): Promise<CompanionCommand[]> {
    await this.desktop(userId, desktopId);
    await this.requireRemoteAccess(userId);
    return this.transaction(async (client) => {
      // Publish state and acknowledge its commands together; a phone never drops an edit before seeing its result.
      await client.query(
        `UPDATE companion_desktops SET last_seen_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), snapshot = COALESCE($2, snapshot), revision = revision + CASE WHEN $2 IS NULL THEN 0 ELSE 1 END WHERE id = $1`,
        [desktopId, snapshot ? JSON.stringify(snapshot) : null]
      );
      for (const receipt of receipts) {
        await client.query(
          'UPDATE companion_commands SET receipt = $3 WHERE id = $1 AND desktop_id = $2 AND receipt IS NULL',
          [receipt.id, desktopId, receipt]
        );
      }
      const { rows } = await client.query<{
        id: string;
        action: CompanionCommand['action'];
      }>(
        `SELECT c.id, c.action FROM companion_commands c JOIN companion_devices d ON d.id = c.device_id WHERE c.desktop_id = $1 AND c.receipt IS NULL AND d.revoked_at IS NULL AND c.id NOT IN (SELECT value FROM json_each($2)) ORDER BY c.sequence LIMIT 50`,
        [desktopId, receipts.map((receipt) => receipt.id)]
      );
      return rows;
    });
  }

  async state(device: DeviceRow, revision: number, commandIds: string[]) {
    await this.requireDeviceAccess(device);
    return this.transaction(async (client) => {
      // Validate the revision after reading both snapshot and receipts, so a concurrent
      // exchange or revocation retries the whole read.
      const { rows } = await client.query<DesktopRow>(
        `
        SELECT desktop.* FROM companion_desktops desktop
        JOIN companion_devices phone ON phone.desktop_id = desktop.id
        WHERE desktop.id = $1 AND phone.id = $2 AND phone.revoked_at IS NULL
        `,
        [device.desktop_id, device.id]
      );
      const desktop = rows[0];
      if (!desktop)
        throw new CompanionError(
          401,
          'This desktop or phone was disconnected.'
        );
      const receipts = await client.query<{ receipt: CompanionReceipt }>(
        'SELECT receipt FROM companion_commands WHERE device_id = $1 AND id IN (SELECT value FROM json_each($2)) AND receipt IS NOT NULL',
        [device.id, commandIds]
      );
      return {
        revision: desktop.revision,
        desktopOnline:
          desktop.last_seen_at !== null &&
          Date.now() - desktop.last_seen_at.getTime() < 75_000,
        snapshot: revision === desktop.revision ? null : desktop.snapshot,
        receipts: receipts.rows.map((row) => row.receipt)
      };
    });
  }
}
