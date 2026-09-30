import { sign } from 'node:crypto';
import { connect } from 'node:http2';
import type { DonyDatabase } from './database';
import { WorkLoop } from './workLoop';

type PushConfig = {
  keyId: string;
  teamId: string;
  privateKey: string;
  topic: string;
};
export class CloudPush {
  private readonly loop = new WorkLoop(() => this.tick());
  constructor(
    private readonly pool: DonyDatabase,
    private readonly config: PushConfig | null
  ) {}
  start() { if (this.config) this.loop.start(); }
  wake() { if (this.config) this.loop.wake(); }
  stop() { this.loop.stop(); }
  private async tick(): Promise<boolean> {
    try {
      const { rows } = await this.pool.query<{
        id: string;
        workspace_id: string;
        thread_id: string;
        title: string;
        body: string;
      }>(
        'SELECT n.* FROM cloud_notifications n JOIN cloud_workspaces w ON w.id = n.workspace_id WHERE n.sent_at IS NULL AND w.pro = true ORDER BY n.created_at LIMIT 20',
        []
      );
      for (const notification of rows) {
        const devices = await this.pool.query<{
          token: string;
          environment: string;
        }>(
          'SELECT token, environment FROM cloud_push_devices WHERE workspace_id = $1',
          [notification.workspace_id]
        );
        for (const device of devices.rows) {
          const response = await this.send(device, notification);
          if (
            response.status === 410 ||
            response.reason === 'BadDeviceToken' ||
            response.reason === 'DeviceTokenNotForTopic'
          )
            await this.pool.query(
              'DELETE FROM cloud_push_devices WHERE workspace_id = $1 AND token = $2',
              [notification.workspace_id, device.token]
            );
          else if (response.status !== 200)
            throw new Error('APNs did not accept the notification.');
        }
        await this.pool.query(
          `UPDATE cloud_notifications SET sent_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = $1`,
          [notification.id]
        );
      }
      return rows.length === 20;
    } catch {
      console.error('Dony push delivery will retry.');
      return false;
    }
  }
  private async send(
    device: { token: string; environment: string },
    notification: { id: string; thread_id: string; title: string; body: string }
  ): Promise<{ status: number; reason?: string }> {
    const config = this.config!;
    const encode = (value: unknown) =>
      Buffer.from(JSON.stringify(value)).toString('base64url');
    const payload = `${encode({ alg: 'ES256', kid: config.keyId })}.${encode({ iss: config.teamId, iat: Math.floor(Date.now() / 1000) })}`;
    const jwt = `${payload}.${sign('sha256', Buffer.from(payload), { key: config.privateKey, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
    return new Promise((resolve, reject) => {
      const client = connect(
        device.environment === 'development'
          ? 'https://api.sandbox.push.apple.com'
          : 'https://api.push.apple.com'
      );
      const timeout = setTimeout(() => {
        client.destroy();
        reject(new Error('APNs timeout.'));
      }, 15_000);
      client.once('error', (error) => {
        clearTimeout(timeout);
        client.destroy();
        reject(error);
      });
      const request = client.request({
        ':method': 'POST',
        ':path': `/3/device/${device.token}`,
        authorization: `bearer ${jwt}`,
        'apns-topic': config.topic,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'apns-collapse-id': notification.id
      });
      let status = 503;
      let body = '';
      request.on('response', (headers) => {
        status = Number(headers[':status']);
      });
      request.on('data', (chunk) => {
        body += String(chunk);
      });
      request.on('end', () => {
        clearTimeout(timeout);
        client.close();
        try {
          resolve({
            status,
            ...(body ? (JSON.parse(body) as { reason?: string }) : {})
          });
        } catch {
          resolve({ status });
        }
      });
      request.on('error', (error) => {
        clearTimeout(timeout);
        client.destroy();
        reject(error);
      });
      request.end(
        JSON.stringify({
          aps: {
            alert: { title: notification.title, body: notification.body },
            sound: 'default'
          },
          threadId: notification.thread_id
        })
      );
    });
  }
}
