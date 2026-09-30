export type BillingPlan = 'connect' | 'pro' | 'plus';
export type BillingPeriod = 'monthly' | 'yearly';

// Public account state deliberately contains no provider costs or dollar budgets.
export type BillingStatus = {
  accountToken: string;
  configured: boolean;
  plan: BillingPlan | null;
  period: BillingPeriod | null;
  monthlyUsedPercent: number;
  extraRemainingPercent: number;
  resetsAt: string | null;
  expiresAt: string | null;
  canRunCloud: boolean;
  canUseRemoteDesktop: boolean;
  limitReached: boolean;
};
