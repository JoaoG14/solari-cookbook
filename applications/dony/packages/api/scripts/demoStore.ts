import { CloudStore } from '../src/cloudStore';

// Local demo only. Production keeps its real subscription and usage checks.
export class DemoStore extends CloudStore {
  override async status(userId: string, configured: boolean) {
    const status = await super.status(userId, configured);
    return { ...status, billing: {
      accountToken: '00000000-0000-4000-8000-000000000001', configured: false,
      plan: null, period: null, monthlyUsedPercent: 0, extraRemainingPercent: 100,
      resetsAt: null, expiresAt: null, canRunCloud: configured,
      canUseRemoteDesktop: false, limitReached: false
    } };
  }
}
