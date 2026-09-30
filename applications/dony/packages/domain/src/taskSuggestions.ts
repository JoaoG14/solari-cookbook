import { z } from 'zod';

import { nonEmptyTrimmedStringSchema } from './shared';

export const taskSuggestionStatusSchema = z.enum([
  'pending',
  'accepted',
  'dismissed',
  'stale'
]);

export type TaskSuggestionStatus = z.infer<typeof taskSuggestionStatusSchema>;

export const taskSuggestionSourceSchema = z.object({
  slug: nonEmptyTrimmedStringSchema,
  name: nonEmptyTrimmedStringSchema
});

export type TaskSuggestionSource = z.infer<typeof taskSuggestionSourceSchema>;

export const taskSuggestionSchema = z.object({
  id: z.string().uuid(),
  source: taskSuggestionSourceSchema,
  sourceItemId: nonEmptyTrimmedStringSchema,
  title: nonEmptyTrimmedStringSchema,
  actionLabel: nonEmptyTrimmedStringSchema,
  summary: nonEmptyTrimmedStringSchema,
  sourceContext: nonEmptyTrimmedStringSchema,
  reason: nonEmptyTrimmedStringSchema,
  instructions: nonEmptyTrimmedStringSchema,
  agentId: z.string().uuid().nullable(),
  status: taskSuggestionStatusSchema,
  taskId: z.string().uuid().nullable(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime()
});

export type TaskSuggestion = z.infer<typeof taskSuggestionSchema>;

export const taskSuggestionsSnapshotSchema = z.object({
  setupStatus: z.enum(['signed_out', 'no_sources', 'ready']),
  syncStatus: z.enum(['idle', 'running', 'error']),
  sources: taskSuggestionSourceSchema.array(),
  suggestions: taskSuggestionSchema.array(),
  lastSuccessfulAt: z.string().datetime().nullable(),
  error: z.string().nullable()
});

export type TaskSuggestionsSnapshot = z.infer<
  typeof taskSuggestionsSnapshotSchema
>;
