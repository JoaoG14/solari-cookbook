import { z } from 'zod';

import { agentSchema } from './agents';
import { agentThreadSchema } from './chat';
import {
  nonEmptyTrimmedStringSchema,
  nullableTrimmedStringSchema
} from './shared';

export const agentQuestionOptionSchema = z.object({
  id: nonEmptyTrimmedStringSchema,
  label: nonEmptyTrimmedStringSchema,
  description: nullableTrimmedStringSchema
});

export type AgentQuestionOption = z.infer<typeof agentQuestionOptionSchema>;

export const agentQuestionResponseKindSchema = z.enum(['text', 'resource']);

export type AgentQuestionResponseKind = z.infer<
  typeof agentQuestionResponseKindSchema
>;

export const agentQuestionItemSchema = z.object({
  id: nonEmptyTrimmedStringSchema,
  header: nullableTrimmedStringSchema,
  question: nonEmptyTrimmedStringSchema,
  options: agentQuestionOptionSchema.array(),
  allowCustomAnswer: z.boolean(),
  multiple: z.boolean().default(false),
  responseKind: agentQuestionResponseKindSchema.optional()
});

export type AgentQuestionItem = z.infer<typeof agentQuestionItemSchema>;

export const agentQuestionSchema = z.object({
  id: z.string().uuid(),
  runId: z.string().uuid(),
  threadId: z.string().uuid(),
  header: nonEmptyTrimmedStringSchema,
  question: nonEmptyTrimmedStringSchema,
  options: agentQuestionOptionSchema.array(),
  allowCustomAnswer: z.boolean(),
  multiple: z.boolean().default(false),
  responseKind: agentQuestionResponseKindSchema.optional(),
  questions: agentQuestionItemSchema.array().min(1),
  createdAt: z.string().datetime()
});

export type AgentQuestion = z.infer<typeof agentQuestionSchema>;

export const agentQuestionAnswerSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('option'),
    questionId: nonEmptyTrimmedStringSchema,
    selectedOptionId: nonEmptyTrimmedStringSchema
  }),
  z.object({
    type: z.literal('options'),
    questionId: nonEmptyTrimmedStringSchema,
    selectedOptionIds: nonEmptyTrimmedStringSchema.array().min(1)
  }),
  z.object({
    type: z.literal('custom'),
    questionId: nonEmptyTrimmedStringSchema,
    customText: nonEmptyTrimmedStringSchema
  })
]);

export type AgentQuestionAnswer = z.infer<typeof agentQuestionAnswerSchema>;

export const agentQuestionResponseSchema = z.discriminatedUnion('action', [
  z.object({
    action: z.literal('accept'),
    answers: agentQuestionAnswerSchema.array(),
    attachments: z
      .object({ path: nonEmptyTrimmedStringSchema })
      .array()
      .optional()
  }),
  z.object({
    action: z.literal('decline')
  }),
  z.object({
    action: z.literal('cancel')
  })
]);

export type AgentQuestionResponse = z.infer<typeof agentQuestionResponseSchema>;

export const pendingAgentQuestionSchema = z.object({
  question: agentQuestionSchema,
  agent: agentSchema,
  thread: agentThreadSchema,
  taskId: z.string().uuid().nullable().default(null)
});

export type PendingAgentQuestion = z.infer<typeof pendingAgentQuestionSchema>;

export const proactiveTaskQuestionSchema = z.object({
  id: z.string().uuid(),
  taskId: z.string().uuid(),
  header: nonEmptyTrimmedStringSchema,
  question: nonEmptyTrimmedStringSchema,
  questions: agentQuestionItemSchema.array().min(1),
  createdAt: z.string().datetime()
});

export type ProactiveTaskQuestion = z.infer<typeof proactiveTaskQuestionSchema>;
