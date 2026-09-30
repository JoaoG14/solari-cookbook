import type { BillingPlan, BillingPeriod } from '@dony/domain';

export const planAllowance = {
  connect: 0,
  pro: 7_000_000,
  plus: 35_000_000
} as const;
export type BillingProduct =
  | { kind: 'subscription'; plan: BillingPlan; period: BillingPeriod }
  | { kind: 'addon'; micros: number };

export const billingProducts: Record<string, BillingProduct> = {
  'com.dony.solari.mobile.connect.monthly': {
    kind: 'subscription', plan: 'connect', period: 'monthly'
  },
  'com.dony.solari.mobile.connect.yearly': {
    kind: 'subscription', plan: 'connect', period: 'yearly'
  },
  'com.dony.solari.mobile.pro.monthly': {
    kind: 'subscription',
    plan: 'pro',
    period: 'monthly'
  },
  'com.dony.solari.mobile.pro.yearly': {
    kind: 'subscription',
    plan: 'pro',
    period: 'yearly'
  },
  'com.dony.solari.mobile.plus.monthly': {
    kind: 'subscription',
    plan: 'plus',
    period: 'monthly'
  },
  'com.dony.solari.mobile.plus.yearly': {
    kind: 'subscription',
    plan: 'plus',
    period: 'yearly'
  },
  'com.dony.solari.mobile.extra.20': { kind: 'addon', micros: 7_000_000 },
  'com.dony.solari.mobile.extra.50': { kind: 'addon', micros: 17_500_000 },
  'com.dony.solari.mobile.extra.100': { kind: 'addon', micros: 35_000_000 }
};

// Clamp to the end of short months without drifting the original anniversary.
export function addMonths(anchor: number, months: number): number {
  const date = new Date(anchor);
  const day = date.getUTCDate();
  date.setUTCDate(1);
  date.setUTCMonth(date.getUTCMonth() + months);
  const lastDay = new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)
  ).getUTCDate();
  date.setUTCDate(Math.min(day, lastDay));
  return date.getTime();
}

export function usageWindow(
  start: number,
  end: number,
  now: number,
  period: BillingPeriod
) {
  let index = 0;
  if (period === 'yearly') {
    while (index < 11 && addMonths(start, index + 1) <= now) index += 1;
  }
  return {
    index,
    start: addMonths(start, index),
    end: period === 'monthly' ? end : Math.min(end, addMonths(start, index + 1))
  };
}
