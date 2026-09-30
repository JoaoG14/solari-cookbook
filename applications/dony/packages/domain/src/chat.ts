import { z } from 'zod';

import { agentSchema } from './agents';
import { codexExecutionModeSchema, providerConfigSchema } from './providers';
import {
  nonEmptyTrimmedStringSchema,
  nullableTrimmedStringSchema
} from './shared';

export const codexRunStatusSchema = z.enum([
  'running',
  'completed',
  'error',
  'canceled'
]);

export type CodexRunStatus = z.infer<typeof codexRunStatusSchema>;

export const codexTimelineEventKindSchema = z.enum([
  'status',
  'reasoning',
  'agent_message',
  'command',
  'file_change',
  'tool',
  'todo',
  'warning',
  'error',
  'raw'
]);

export type CodexTimelineEventKind = z.infer<
  typeof codexTimelineEventKindSchema
>;

export const agentThreadOriginSchema = z.enum(['direct', 'task']);

export type AgentThreadOrigin = z.infer<typeof agentThreadOriginSchema>;

export const agentThreadSchema = z.object({
  id: z.string().uuid(),
  agentId: z.string().uuid(),
  origin: agentThreadOriginSchema.default('direct'),
  taskId: z.string().uuid().nullable().default(null),
  title: nonEmptyTrimmedStringSchema,
  isDefault: z.boolean(),
  codexSessionId: nullableTrimmedStringSchema,
  browserProfileId: z.string().uuid().nullable(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
  viewedAt: z.string().datetime().nullable().optional(),
  archivedAt: z.string().datetime().nullable()
});

export type AgentThread = z.infer<typeof agentThreadSchema>;

export const taskChatExpiresAt = (
  thread: AgentThread,
  task: { status: string } | undefined
): number | null => {
  if (thread.origin !== 'task' || task?.status !== 'done' || !thread.viewedAt) {
    return null;
  }

  return Date.parse(thread.viewedAt) + 24 * 60 * 60 * 1000;
};

export const createAgentThreadInputSchema = z
  .object({
    agentId: z.string().uuid(),
    title: nonEmptyTrimmedStringSchema,
    origin: agentThreadOriginSchema.default('direct'),
    taskId: z.string().uuid().nullable().default(null)
  })
  .superRefine((value, context) => {
    if (value.origin === 'task' && value.taskId === null) {
      context.addIssue({
        code: 'custom',
        path: ['taskId'],
        message: 'Task threads require a task id.'
      });
    }

    if (value.origin === 'direct' && value.taskId !== null) {
      context.addIssue({
        code: 'custom',
        path: ['taskId'],
        message: 'Direct threads cannot reference a task.'
      });
    }
  });

export type CreateAgentThreadInput = z.input<
  typeof createAgentThreadInputSchema
>;

export const agentMessageRoleSchema = z.enum(['user', 'assistant', 'system']);

export type AgentMessageRole = z.infer<typeof agentMessageRoleSchema>;

export const agentMessageStatusSchema = z.enum([
  'complete',
  'pending',
  'error'
]);

export type AgentMessageStatus = z.infer<typeof agentMessageStatusSchema>;

export const agentMessageSchema = z.object({
  id: z.string().uuid(),
  threadId: z.string().uuid(),
  role: agentMessageRoleSchema,
  content: z.string(),
  status: agentMessageStatusSchema,
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
  providerMetadata: z.string().nullable()
});

export type AgentMessage = z.infer<typeof agentMessageSchema>;

export const codexRunSchema = z.object({
  id: z.string().uuid(),
  threadId: z.string().uuid(),
  assistantMessageId: z.string().uuid(),
  status: codexRunStatusSchema,
  command: nonEmptyTrimmedStringSchema,
  cwd: nonEmptyTrimmedStringSchema,
  model: nullableTrimmedStringSchema,
  profile: nullableTrimmedStringSchema,
  executionMode: codexExecutionModeSchema,
  codexSessionId: nullableTrimmedStringSchema,
  startedAt: z.string().datetime(),
  completedAt: z.string().datetime().nullable(),
  error: z.string().nullable()
});

export type CodexRun = z.infer<typeof codexRunSchema>;

export const codexTimelineEventSchema = z.object({
  id: z.string().uuid(),
  runId: z.string().uuid(),
  assistantMessageId: z.string().uuid(),
  sequence: z.number().int().nonnegative(),
  kind: codexTimelineEventKindSchema,
  title: nonEmptyTrimmedStringSchema,
  detail: z.string().nullable(),
  metadata: z.string().nullable(),
  createdAt: z.string().datetime()
});

export type CodexTimelineEvent = z.infer<typeof codexTimelineEventSchema>;

export const agentThreadSummarySchema = z.object({
  thread: agentThreadSchema,
  agent: agentSchema,
  providerConfig: providerConfigSchema,
  latestMessage: agentMessageSchema
});

export type AgentThreadSummary = z.infer<typeof agentThreadSummarySchema>;
