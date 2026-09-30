import { z } from 'zod';

import { nonEmptyTrimmedStringSchema } from './shared';

export const computerUseActivitySchema = z.object({
  runId: z.string().uuid(),
  state: z.enum(['running', 'paused']),
  appName: nonEmptyTrimmedStringSchema.nullable(),
  action: nonEmptyTrimmedStringSchema
});

export type ComputerUseActivity = z.infer<typeof computerUseActivitySchema>;

export const computerUseAllowedAppSchema = z.object({
  id: nonEmptyTrimmedStringSchema,
  name: nonEmptyTrimmedStringSchema,
  bundleId: nonEmptyTrimmedStringSchema.nullable()
});

export type ComputerUseAllowedApp = z.infer<typeof computerUseAllowedAppSchema>;
