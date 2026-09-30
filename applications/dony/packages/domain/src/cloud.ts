import { z } from 'zod';
import { companionCommandSchema, companionSnapshotSchema } from './companion';
import { taughtMethodSchema } from './teaching';

export const cloudExecutionTargetSchema = z.enum(['cloud', 'computer']);
export type CloudExecutionTarget = z.infer<typeof cloudExecutionTargetSchema>;

export const cloudSnapshotSchema = companionSnapshotSchema.extend({
  context: z.string().max(100_000).default(''),
  skills: taughtMethodSchema.array().max(100).default([])
});
export type CloudSnapshot = z.infer<typeof cloudSnapshotSchema>;

export const cloudCommandSchema = companionCommandSchema.extend({
  executionTarget: cloudExecutionTargetSchema.default('cloud'),
  // Computer execution is sent over the paired local connection in this release.
  desktopId: z.string().uuid().optional()
});
export type CloudCommand = z.infer<typeof cloudCommandSchema>;

export const cloudExchangeSchema = z.object({
  id: z.string().uuid(),
  desktopId: z.string().uuid(),
  name: z.string().trim().min(1).max(100),
  base: cloudSnapshotSchema.nullable(),
  snapshot: cloudSnapshotSchema
});
export type CloudExchange = z.infer<typeof cloudExchangeSchema>;

export type CloudStatus = {
  workspaceId: string;
  pro: boolean;
  executionTarget: CloudExecutionTarget;
  dailyLimitUsd: number;
  dailySpentUsd: number;
  resetsAt: string;
  configured: boolean;
  billing?: import('./billing').BillingStatus;
};

export const emptyCloudSnapshot = (): CloudSnapshot => ({
  version: 1,
  mode: 'off',
  tasks: [],
  agents: [],
  threads: [],
  results: [],
  context: '',
  skills: []
});

// Merge only fields a device changed since its last acknowledgement. A stale
// device cannot replace the workspace or erase work completed in the cloud.
export function mergeCloudSnapshot(
  current: CloudSnapshot,
  base: CloudSnapshot,
  incoming: CloudSnapshot
): { snapshot: CloudSnapshot; conflicts: string[] } {
  const conflicts: string[] = [];
  const same = (a: unknown, b: unknown) =>
    JSON.stringify(a) === JSON.stringify(b);
  const merge = (
    value: unknown,
    before: unknown,
    after: unknown,
    path: string
  ): unknown => {
    if (same(before, after) || same(value, after)) return value;
    if (same(value, before)) return after;
    const records = (v: unknown): v is Array<{ id: string }> =>
      Array.isArray(v) &&
      v.every(
        (item: unknown) =>
          item !== null &&
          typeof item === 'object' &&
          'id' in item &&
          typeof item.id === 'string'
      );
    if (records(value) && records(before) && records(after)) {
      const old = new Map(before.map((item) => [item.id, item]));
      const next = new Map(after.map((item) => [item.id, item]));
      const live = new Map(value.map((item) => [item.id, item]));
      for (const id of new Set([...old.keys(), ...next.keys()])) {
        const item = merge(
          live.get(id),
          old.get(id),
          next.get(id),
          `${path}/${id}`
        );
        if (item === undefined) live.delete(id);
        else live.set(id, item as { id: string });
      }
      return [...live.values()];
    }
    const object = (v: unknown): v is Record<string, unknown> =>
      v !== null && typeof v === 'object' && !Array.isArray(v);
    if (object(value) && object(before) && object(after)) {
      const result = { ...value };
      for (const key of new Set([
        ...Object.keys(before),
        ...Object.keys(after)
      ])) {
        // Timestamps describe the accepted content; they are not conflict clocks.
        if (key === 'updatedAt') continue;
        result[key] = merge(
          value[key],
          before[key],
          after[key],
          `${path}/${key}`
        );
      }
      if (!same(result, value) && 'updatedAt' in value)
        result.updatedAt = new Date().toISOString();
      return result;
    }
    conflicts.push(path);
    return value;
  };
  return {
    snapshot: cloudSnapshotSchema.parse(
      merge(current, base, incoming, 'workspace')
    ),
    conflicts
  };
}
