import { z } from 'zod';
import { chatThinkingSchema } from './chatThinking';
import { agentSchema } from './agents';
import { agentMessageSchema, agentThreadSchema } from './chat';
import { agentQuestionSchema, agentQuestionAnswerSchema } from './questions';
import { agentsModeSchema } from './settings';
import {
  taskSchema,
  createTaskInputSchema,
  updateTaskPatchSchema,
  reorderTasksInputSchema
} from './tasks';
import { homeTaskAgentResultSchema } from './taskResults';

const id = z.string().uuid();
export const companionPairRequestSchema = z.object({
  code: z.string().min(24).max(64),
  name: z.string().trim().min(1).max(100)
});
export const companionStateRequestSchema = z.object({
  revision: z.number().int().min(-1).optional(),
  commandIds: id.array().max(100)
});
export const companionFileSchema = z.object({
  name: z.string().trim().min(1).max(255),
  base64: z
    .string()
    .max(28_000_000)
    .regex(/^[A-Za-z0-9+/]*={0,2}$/)
    .refine((value) => value.length % 4 === 0, 'Invalid base64 data'),
  mimeType: z.string().max(100).default('application/octet-stream')
});
export const companionQuestionResponseSchema = z.discriminatedUnion('action', [
  z.object({
    action: z.literal('accept'),
    answers: agentQuestionAnswerSchema.array(),
    files: companionFileSchema.array().max(5).default([])
  }),
  z.object({ action: z.literal('decline') }),
  z.object({ action: z.literal('cancel') })
]);

// A deliberately small command surface. Local paths and arbitrary IPC are never accepted.
export const companionActionSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('task.create'),
    taskId: id,
    input: createTaskInputSchema
  }),
  z.object({
    type: z.literal('task.update'),
    taskId: id,
    expectedUpdatedAt: z.string(),
    patch: updateTaskPatchSchema
  }),
  z.object({
    type: z.literal('task.delete'),
    taskId: id,
    expectedUpdatedAt: z.string()
  }),
  z.object({
    type: z.literal('task.reorder'),
    input: reorderTasksInputSchema,
    expectedOrder: id.array()
  }),
  z.object({
    type: z.literal('mode.set'),
    mode: agentsModeSchema,
    expectedMode: agentsModeSchema
  }),
  z.object({ type: z.literal('chat.create'), threadId: id, agentId: id }),
  z.object({
    type: z.literal('chat.send'),
    threadId: id,
    thinking: chatThinkingSchema.optional(),
    message: z.string().max(100_000),
    files: companionFileSchema.array().max(5).default([])
  }),
  z.object({ type: z.literal('chat.archive'), threadId: id }),
  z.object({
    type: z.literal('chat.viewed'),
    threadId: id,
    viewedAt: z.string().datetime()
  }),
  z.object({ type: z.literal('run.stop'), threadId: id, runId: id }),
  z.object({
    type: z.literal('question.answer'),
    questionId: id,
    taskId: id.nullable(),
    response: companionQuestionResponseSchema
  }),
  z.object({
    type: z.literal('task.suggestion'),
    taskId: id,
    expectedUpdatedAt: z.string(),
    action: z.enum(['accept', 'dismiss', 'retry'])
  }),
  z.object({
    type: z.literal('task.review'),
    resultId: id,
    action: z.enum(['accept', 'changes']),
    feedback: z.string().max(100_000).default('')
  }),
  z.object({
    type: z.literal('result.dismiss'),
    resultId: id
  }),
  z.object({
    type: z.literal('artifact.read'),
    resultId: id,
    index: z.number().int().nonnegative()
  })
]);
export type CompanionAction = z.infer<typeof companionActionSchema>;
export const companionCommandSchema = z.object({
  id,
  action: companionActionSchema
});
export type CompanionCommand = z.infer<typeof companionCommandSchema>;
export const companionReceiptSchema = z.object({
  id,
  status: z.enum(['completed', 'conflict', 'failed']),
  error: z.string().nullable(),
  file: companionFileSchema.optional(),
  taskVersions: z
    .record(
      z.string(),
      z.object({ before: z.string().nullable(), after: z.string() })
    )
    .optional()
});
export type CompanionReceipt = z.infer<typeof companionReceiptSchema>;

export const companionAgentSchema = agentSchema.pick({
  id: true,
  name: true,
  emoji: true,
  color: true,
  instructions: true,
  welcomeMessage: true,
  modelOverride: true,
  updatedAt: true
});
export const companionAnsweredQuestionSchema = z.object({
  id,
  header: z.string(),
  answers: z.object({ question: z.string(), answer: z.string() }).array()
});
export const companionThreadSchema = agentThreadSchema
  .pick({
    id: true,
    agentId: true,
    origin: true,
    taskId: true,
    title: true,
    createdAt: true,
    updatedAt: true,
    archivedAt: true,
    viewedAt: true
  })
  .extend({
    messages: agentMessageSchema
      .omit({ providerMetadata: true })
      .extend({
        questionAnswer: companionAnsweredQuestionSchema.optional()
      })
      .array(),
    runId: id.nullable(),
    executionTarget: z.enum(['cloud', 'computer']).optional(),
    thinking: chatThinkingSchema.optional(),
    status: z.enum(['ready', 'running', 'failed', 'blocked']),
    activity: z.string().nullable(),
    instanceNumber: z.number().int().positive().nullable(),
    sidebarExpiresAt: z.string().datetime().nullable().optional(),
    question: agentQuestionSchema.nullable()
  });
export const companionResultSchema = homeTaskAgentResultSchema
  .omit({ artifacts: true })
  .extend({
    artifacts: z
      .object({
        name: z.string(),
        cloudArtifactId: id.optional(),
        type: z.enum(['file', 'task_output', 'link']),
        url: z.string().url().optional()
      })
      .array()
  });
export const companionSnapshotSchema = z.object({
  version: z.literal(1),
  mode: agentsModeSchema,
  tasks: taskSchema.array(),
  agents: companionAgentSchema.array(),
  threads: companionThreadSchema.array(),
  results: companionResultSchema.array()
});
export type CompanionSnapshot = z.infer<typeof companionSnapshotSchema>;
export const companionExchangeSchema = z.object({
  snapshot: companionSnapshotSchema.optional(),
  receipts: companionReceiptSchema.array().max(100).default([])
});
export const companionDeviceSchema = z.object({
  id,
  name: z.string(),
  createdAt: z.string()
});
export const companionDesktopStatusSchema = z.object({
  enabled: z.boolean(),
  connected: z.boolean(),
  desktopId: id.nullable(),
  accountId: z.string().nullable(),
  devices: companionDeviceSchema.array(),
  error: z.string().nullable()
});
export type CompanionDesktopStatus = z.infer<
  typeof companionDesktopStatusSchema
>;
export type CompanionPairing = { url: string; code: string; expiresAt: string };
export interface CompanionApi {
  cloudStatus?(): Promise<import('./cloud').CloudStatus & { error: string | null }>;
  cloudSettings?(patch: { pro?: boolean; executionTarget?: 'cloud' | 'computer' }): Promise<import('./cloud').CloudStatus>;
  status(): Promise<CompanionDesktopStatus>;
  pair(): Promise<CompanionPairing>;
  revoke(deviceId: string): Promise<void>;
  disconnect(): Promise<void>;
}
export const companionIpcChannels = {
  cloudStatus: 'companion:cloud-status',
  cloudSettings: 'companion:cloud-settings',
  status: 'companion:status',
  pair: 'companion:pair',
  revoke: 'companion:revoke',
  disconnect: 'companion:disconnect'
} as const;

// Interactive connector requests are never queued for later offline replay.
export const companionConnectorRequestSchema = z.discriminatedUnion('action', [
  z.object({ action: z.literal('list') }),
  z.object({ action: z.literal('suggestEmailTasks'), toolkit: z.enum(['gmail', 'outlook']).optional() }),
  z.object({
    action: z.literal('connect'),
    toolkit: z.string().regex(/^[a-zA-Z0-9_-]{1,100}$/)
  }),
  z.object({
    action: z.literal('refresh'),
    connectedAccountId: z.string().min(1).max(200)
  }),
  z.object({
    action: z.literal('disconnect'),
    connectedAccountId: z.string().min(1).max(200)
  }),
  z.object({
    action: z.literal('setEnabled'),
    connectedAccountId: z.string().min(1).max(200),
    enabled: z.boolean()
  })
]);
export type CompanionConnectorRequest = z.infer<
  typeof companionConnectorRequestSchema
>;
