import { z } from 'zod';

import { nonEmptyTrimmedStringSchema } from './shared';

export const contextInsightCategorySchema = z.enum([
  'project',
  'recent_focus',
  'working_pattern',
  'tool_usage'
]);

export type ContextInsightCategory = z.infer<
  typeof contextInsightCategorySchema
>;

export const contextInsightSchema = z.object({
  id: nonEmptyTrimmedStringSchema,
  sourceSlug: nonEmptyTrimmedStringSchema,
  sourceName: nonEmptyTrimmedStringSchema,
  sourceItemId: nonEmptyTrimmedStringSchema,
  sourceTitle: nonEmptyTrimmedStringSchema,
  category: contextInsightCategorySchema,
  summary: nonEmptyTrimmedStringSchema,
  confidence: z.number().min(0).max(1),
  observedAt: z.string().datetime(),
  expiresAt: z.string().datetime()
});

export type ContextInsight = z.infer<typeof contextInsightSchema>;

export const contextExtractorSourceSchema = z.object({
  slug: nonEmptyTrimmedStringSchema,
  name: nonEmptyTrimmedStringSchema,
  lastSuccessfulAt: z.string().datetime().nullable(),
  error: z.string().nullable()
});

export type ContextExtractorSource = z.infer<
  typeof contextExtractorSourceSchema
>;

export const contextExtractorSnapshotSchema = z.object({
  setupStatus: z.enum(['signed_out', 'no_context', 'no_sources', 'ready']),
  syncStatus: z.enum(['idle', 'running', 'error']),
  sources: contextExtractorSourceSchema.array(),
  insights: contextInsightSchema.array(),
  lastSuccessfulAt: z.string().datetime().nullable(),
  lastConsolidatedAt: z.string().datetime().nullable(),
  nextScheduledAt: z.string().datetime().nullable(),
  error: z.string().nullable()
});

export type ContextExtractorSnapshot = z.infer<
  typeof contextExtractorSnapshotSchema
>;
