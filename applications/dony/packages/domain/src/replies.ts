import { z } from 'zod';

import { nonEmptyTrimmedStringSchema } from './shared';

export const replySuggestionStatusSchema = z.enum([
  'pending',
  'sent',
  'dismissed',
  'stale'
]);

export type ReplySuggestionStatus = z.infer<typeof replySuggestionStatusSchema>;

export const replyThreadMessageSchema = z.object({
  id: nonEmptyTrimmedStringSchema,
  sender: nonEmptyTrimmedStringSchema,
  to: z.string(),
  text: z.string(),
  receivedAt: z.string().datetime()
});

export type ReplyThreadMessage = z.infer<typeof replyThreadMessageSchema>;

export const replySuggestedTaskSchema = z.object({
  title: nonEmptyTrimmedStringSchema.max(200),
  instructions: nonEmptyTrimmedStringSchema.max(5_000),
  agentId: z.string().uuid().nullable(),
  threadId: z.string().uuid().nullable(),
  startedAt: z.string().datetime().nullable()
});

export type ReplySuggestedTask = z.infer<typeof replySuggestedTaskSchema>;

export const replySuggestionSchema = z.object({
  id: z.string().uuid(),
  userId: nonEmptyTrimmedStringSchema,
  mailboxEmail: z.string().email(),
  threadId: nonEmptyTrimmedStringSchema,
  sourceMessageId: nonEmptyTrimmedStringSchema,
  senderName: z.string().nullable(),
  senderEmail: z.string().email(),
  subject: z.string(),
  snippet: z.string(),
  receivedAt: z.string().datetime(),
  reason: nonEmptyTrimmedStringSchema,
  confidence: z.number().min(0).max(1),
  priority: z.enum(['normal', 'high']),
  draft: nonEmptyTrimmedStringSchema,
  suggestedTask: replySuggestedTaskSchema.nullable(),
  thread: replyThreadMessageSchema.array(),
  status: replySuggestionStatusSchema,
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
  sentAt: z.string().datetime().nullable(),
  dismissedAt: z.string().datetime().nullable()
});

export type ReplySuggestion = z.infer<typeof replySuggestionSchema>;

export const repliesSetupStatusSchema = z.enum([
  'signed_out',
  'gmail_not_connected',
  'ready'
]);

export type RepliesSetupStatus = z.infer<typeof repliesSetupStatusSchema>;

export const replySyncStatusSchema = z.enum(['idle', 'running', 'error']);

export const repliesSnapshotSchema = z.object({
  setupStatus: repliesSetupStatusSchema,
  mailboxEmail: z.string().email().nullable(),
  suggestions: replySuggestionSchema.array(),
  syncStatus: replySyncStatusSchema,
  lastAttemptAt: z.string().datetime().nullable(),
  lastSuccessfulAt: z.string().datetime().nullable(),
  lastError: z.string().nullable(),
  nextScheduledAt: z.string().datetime().nullable()
});

export type RepliesSnapshot = z.infer<typeof repliesSnapshotSchema>;

export const updateReplyDraftInputSchema = z.object({
  id: z.string().uuid(),
  draft: nonEmptyTrimmedStringSchema.max(20_000)
});

export type UpdateReplyDraftInput = z.infer<typeof updateReplyDraftInputSchema>;

export const startReplyTaskInputSchema = z.object({
  replySuggestionId: z.string().uuid(),
  agentId: z.string().uuid()
});

export type StartReplyTaskInput = z.infer<typeof startReplyTaskInputSchema>;

export const startReplyTaskResultSchema = z.object({
  agentId: z.string().uuid(),
  threadId: z.string().uuid()
});

export type StartReplyTaskResult = z.infer<typeof startReplyTaskResultSchema>;
