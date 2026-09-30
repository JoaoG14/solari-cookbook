import { z } from 'zod';

import {
  codexExecutionModeSchema,
  modelEffortSchema,
  modelServiceTierSchema
} from './providers';
import {
  nonEmptyTrimmedStringSchema,
  nullableTrimmedStringSchema
} from './shared';

export const agentSchema = z.object({
  id: z.string().uuid(),
  name: nonEmptyTrimmedStringSchema,
  emoji: nonEmptyTrimmedStringSchema,
  color: nonEmptyTrimmedStringSchema,
  instructions: z.string(),
  welcomeMessage: nullableTrimmedStringSchema,
  providerConfigId: z.string().uuid(),
  cwd: nonEmptyTrimmedStringSchema,
  modelOverride: nullableTrimmedStringSchema,
  modelEffort: modelEffortSchema.nullable(),
  modelServiceTier: modelServiceTierSchema,
  codexCommand: nonEmptyTrimmedStringSchema,
  codexProfile: nullableTrimmedStringSchema,
  codexExecutionMode: codexExecutionModeSchema,
  defaultBrowserProfileId: z.string().uuid().nullable(),
  sidebarOrder: z.number().int().nonnegative(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
  deletedAt: z.string().datetime().nullable()
});

export type Agent = z.infer<typeof agentSchema>;

export const createAgentInputSchema = z.object({
  name: nonEmptyTrimmedStringSchema,
  emoji: nonEmptyTrimmedStringSchema,
  color: nonEmptyTrimmedStringSchema,
  instructions: z.string().optional(),
  providerConfigId: z.string().uuid().optional(),
  cwd: nonEmptyTrimmedStringSchema,
  modelOverride: nullableTrimmedStringSchema.optional(),
  modelEffort: modelEffortSchema.nullable().optional(),
  modelServiceTier: modelServiceTierSchema.optional(),
  codexCommand: nonEmptyTrimmedStringSchema.optional(),
  codexProfile: nullableTrimmedStringSchema.optional(),
  codexExecutionMode: codexExecutionModeSchema.optional(),
  defaultBrowserProfileId: z.string().uuid().nullable().optional(),
  sidebarOrder: z.number().int().nonnegative().optional()
});

export type CreateAgentInput = z.infer<typeof createAgentInputSchema>;

export const agentWelcomeContextInputSchema = z.object({
  preferredName: nullableTrimmedStringSchema
});

export type AgentWelcomeContextInput = z.infer<
  typeof agentWelcomeContextInputSchema
>;

export const updateAgentPatchSchema = z
  .object({
    name: nonEmptyTrimmedStringSchema.optional(),
    emoji: nonEmptyTrimmedStringSchema.optional(),
    color: nonEmptyTrimmedStringSchema.optional(),
    instructions: z.string().optional(),
    providerConfigId: z.string().uuid().optional(),
    cwd: nonEmptyTrimmedStringSchema.optional(),
    modelOverride: nullableTrimmedStringSchema.optional(),
    modelEffort: modelEffortSchema.nullable().optional(),
    modelServiceTier: modelServiceTierSchema.optional(),
    codexCommand: nonEmptyTrimmedStringSchema.optional(),
    codexProfile: nullableTrimmedStringSchema.optional(),
    codexExecutionMode: codexExecutionModeSchema.optional(),
    defaultBrowserProfileId: z.string().uuid().nullable().optional(),
    sidebarOrder: z.number().int().nonnegative().optional(),
    deletedAt: z.string().datetime().nullable().optional()
  })
  .refine((value) => Object.keys(value).length > 0, {
    message: 'Update patch cannot be empty.'
  });

export type UpdateAgentPatch = z.infer<typeof updateAgentPatchSchema>;
