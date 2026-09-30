import { z } from 'zod';

import { agentResponseLanguageSchema } from './agentResponseLanguages';
import { codexTimelineEventKindSchema } from './chat';
import {
  modelEffortSchema,
  modelServiceTierSchema,
  providerTypeSchema
} from './providers';
import {
  nonEmptyTrimmedStringSchema,
  nullableTrimmedStringSchema
} from './shared';
import { taskResultArtifactSchema } from './taskResults';
import { taskOutputDesignSchema } from './taskOutputDesigns';
import { taskScreenshotImportInputSchema } from './tasks';

export const nativeAgentLocalToolNameSchema = z.enum([
  'filesystem_list_directory',
  'filesystem_read_text_file',
  'filesystem_create_directory',
  'filesystem_move_file',
  'filesystem_write_text_file',
  'computer_use',
  'browser',
  'connector_use',
  'publish_task_output',
  'memory_search',
  'memory_read',
  'memory_write',
  'chat_search',
  'chat_read',
  'ask_user'
]);

export type NativeAgentLocalToolName = z.infer<
  typeof nativeAgentLocalToolNameSchema
>;

export const nativeAgentLocalToolCallSchema = z.object({
  id: nonEmptyTrimmedStringSchema,
  name: nativeAgentLocalToolNameSchema,
  arguments: z.unknown()
});

export type NativeAgentLocalToolCall = z.infer<
  typeof nativeAgentLocalToolCallSchema
>;

export const nativeAgentLocalToolResultSchema = z.object({
  callId: nonEmptyTrimmedStringSchema,
  status: z.enum(['success', 'error']),
  content: z.string(),
  images: z
    .array(
      z.object({
        data: z.string(),
        mimeType: z.enum(['image/png', 'image/jpeg', 'image/webp'])
      })
    )
    .optional(),
  metadata: z.unknown().nullable().optional()
});

export type NativeAgentLocalToolResult = z.infer<
  typeof nativeAgentLocalToolResultSchema
>;

export const nativeAgentLocalToolResultInputSchema = z.object({
  runId: z.string().uuid(),
  result: nativeAgentLocalToolResultSchema
});

export type NativeAgentLocalToolResultInput = z.infer<
  typeof nativeAgentLocalToolResultInputSchema
>;

export const nativeAgentTranscriptMessageSchema = z.object({
  role: z.enum(['user', 'assistant', 'system']),
  content: z.string()
});

export type NativeAgentTranscriptMessage = z.infer<
  typeof nativeAgentTranscriptMessageSchema
>;

export const nativeAgentRunRequestSchema = z.object({
  runId: z.string().uuid().optional(),
  threadId: z.string().uuid(),
  agent: z.object({
    id: z.string().uuid(),
    name: nonEmptyTrimmedStringSchema,
    instructions: z.string(),
    cwd: nonEmptyTrimmedStringSchema
  }),
  message: nonEmptyTrimmedStringSchema,
  transcript: nativeAgentTranscriptMessageSchema.array(),
  model: nullableTrimmedStringSchema,
  modelProviderType: providerTypeSchema.optional(),
  modelEffort: modelEffortSchema.nullable(),
  modelServiceTier: modelServiceTierSchema.optional(),
  agentResponseLanguage: agentResponseLanguageSchema.optional(),
  outputSchema: z.record(z.string(), z.unknown()).optional(),
  images: taskScreenshotImportInputSchema.array().max(20).optional(),
  localTools: nativeAgentLocalToolNameSchema.array().optional(),
  taskOutputDesign: taskOutputDesignSchema.optional()
});

export type NativeAgentRunRequest = z.infer<typeof nativeAgentRunRequestSchema>;

export const nativeAgentTimelineEventDraftSchema = z.object({
  kind: codexTimelineEventKindSchema,
  title: nonEmptyTrimmedStringSchema,
  detail: z.string().nullable().optional(),
  metadata: z.unknown().nullable().optional()
});

export type NativeAgentTimelineEventDraft = z.infer<
  typeof nativeAgentTimelineEventDraftSchema
>;

export const nativeAgentRunResponseSchema = z.object({
  content: z.string(),
  providerSessionId: nullableTrimmedStringSchema.optional(),
  resultArtifacts: taskResultArtifactSchema.array().optional(),
  timelineEvents: nativeAgentTimelineEventDraftSchema.array().optional()
});

export type NativeAgentRunResponse = z.infer<
  typeof nativeAgentRunResponseSchema
>;

export const nativeAgentStreamEventSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('timeline'),
    event: nativeAgentTimelineEventDraftSchema
  }),
  z.object({
    type: z.literal('assistant_delta'),
    delta: z.string()
  }),
  z.object({
    type: z.literal('local_tool_call'),
    call: nativeAgentLocalToolCallSchema
  }),
  z.object({
    type: z.literal('local_tool_result'),
    result: nativeAgentLocalToolResultSchema
  }),
  z.object({
    type: z.literal('completed'),
    content: z.string(),
    resultArtifacts: taskResultArtifactSchema.array().optional(),
    providerSessionId: nullableTrimmedStringSchema.optional()
  }),
  z.object({
    type: z.literal('error'),
    message: nonEmptyTrimmedStringSchema
  })
]);

export type NativeAgentStreamEvent = z.infer<
  typeof nativeAgentStreamEventSchema
>;
