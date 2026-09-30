import { z } from 'zod';

import { nonEmptyTrimmedStringSchema } from './shared';

export const memorySpaceSchema = z.object({
  id: z.string().uuid(),
  name: nonEmptyTrimmedStringSchema,
  rootPath: nonEmptyTrimmedStringSchema,
  isActive: z.boolean(),
  createdAt: z.string(),
  updatedAt: z.string()
});

export type MemorySpace = z.infer<typeof memorySpaceSchema>;

export const memoryFileKindSchema = z.enum([
  'profile',
  'index',
  'schema',
  'inbox',
  'log',
  'page',
  'project',
  'raw',
  'other'
]);

export type MemoryFileKind = z.infer<typeof memoryFileKindSchema>;

export const memoryFileSummarySchema = z.object({
  path: nonEmptyTrimmedStringSchema,
  title: nonEmptyTrimmedStringSchema,
  kind: memoryFileKindSchema,
  size: z.number().int().nonnegative(),
  updatedAt: z.string()
});

export type MemoryFileSummary = z.infer<typeof memoryFileSummarySchema>;

export const memoryDocumentSchema = memoryFileSummarySchema.extend({
  content: z.string(),
  hash: nonEmptyTrimmedStringSchema
});

export type MemoryDocument = z.infer<typeof memoryDocumentSchema>;

export const memorySearchResultSchema = z.object({
  path: nonEmptyTrimmedStringSchema,
  title: nonEmptyTrimmedStringSchema,
  excerpt: z.string(),
  line: z.number().int().positive()
});

export type MemorySearchResult = z.infer<typeof memorySearchResultSchema>;

export const memoryProposalSchema = z.object({
  id: z.string().uuid(),
  spaceId: z.string().uuid(),
  path: nonEmptyTrimmedStringSchema,
  proposedContent: z.string(),
  baseHash: z.string().nullable(),
  reason: z.string(),
  sourceAgentId: z.string().uuid().nullable(),
  createdAt: z.string()
});

export type MemoryProposal = z.infer<typeof memoryProposalSchema>;

export const memorySnapshotSchema = z.object({
  spaces: memorySpaceSchema.array(),
  activeSpace: memorySpaceSchema.nullable(),
  files: memoryFileSummarySchema.array(),
  pendingProposals: memoryProposalSchema.array(),
  isGitRepository: z.boolean()
});

export type MemorySnapshot = z.infer<typeof memorySnapshotSchema>;

export const fixedMemoryPages = [
  { key: 'context', label: 'Context', path: 'CONTEXT.md' }
] as const;

export type FixedMemoryPageKey = (typeof fixedMemoryPages)[number]['key'];

export const createMemorySpaceInputSchema = z.object({
  name: nonEmptyTrimmedStringSchema,
  parentPath: nonEmptyTrimmedStringSchema,
  context: z
    .object({
      preferredName: nonEmptyTrimmedStringSchema,
      role: nonEmptyTrimmedStringSchema,
      currentFocus: nonEmptyTrimmedStringSchema,
      projects: nonEmptyTrimmedStringSchema,
      workingStyle: nonEmptyTrimmedStringSchema,
      toolsByActivity: z.string()
    })
    .optional()
});

export type CreateMemorySpaceInput = z.infer<
  typeof createMemorySpaceInputSchema
>;

export const attachMemorySpaceInputSchema = z.object({
  rootPath: nonEmptyTrimmedStringSchema,
  name: z.string().optional()
});

export type AttachMemorySpaceInput = z.infer<
  typeof attachMemorySpaceInputSchema
>;

export const saveMemoryDocumentInputSchema = z.object({
  path: nonEmptyTrimmedStringSchema,
  content: z.string(),
  expectedHash: z.string().nullable()
});

export type SaveMemoryDocumentInput = z.infer<
  typeof saveMemoryDocumentInputSchema
>;

export const rememberMemoryInputSchema = z.object({
  title: nonEmptyTrimmedStringSchema,
  content: nonEmptyTrimmedStringSchema,
  source: nonEmptyTrimmedStringSchema
});

export type RememberMemoryInput = z.infer<typeof rememberMemoryInputSchema>;
