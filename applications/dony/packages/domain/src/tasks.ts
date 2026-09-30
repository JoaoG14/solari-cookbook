import { z } from 'zod';

import { nonEmptyTrimmedStringSchema } from './shared';
import { proactiveTaskQuestionSchema } from './questions';

export const taskStatusSchema = z.enum(['todo', 'done']);

export type TaskStatus = z.infer<typeof taskStatusSchema>;

export const taskDueDateSchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'Due date must use YYYY-MM-DD.')
  .refine((value) => {
    const date = new Date(`${value}T00:00:00.000Z`);

    return (
      !Number.isNaN(date.getTime()) && date.toISOString().startsWith(value)
    );
  }, 'Due date must be a valid calendar date.');

export const proactivePlanningStatusSchema = z.enum(['pending', 'failed']);

export type ProactivePlanningStatus = z.infer<
  typeof proactivePlanningStatusSchema
>;

export const proactiveExecutionStatusSchema = z.enum([
  'queued',
  'running',
  'blocked',
  'failed'
]);

export type ProactiveExecutionStatus = z.infer<
  typeof proactiveExecutionStatusSchema
>;

export const proactiveTaskOwnershipSchema = z.enum([
  'human',
  'agent',
  'hybrid'
]);

export type ProactiveTaskOwnership = z.infer<
  typeof proactiveTaskOwnershipSchema
>;

export const normalizeProactiveSuggestionLabel = (
  label: string | null | undefined
): string => {
  const action = label
    ?.trim()
    .match(/^[\p{L}\p{N}]+(?:['’-][\p{L}\p{N}]+)*/u)?.[0];

  if (!action || /^(?:ai|with)$/iu.test(action)) {
    return 'Do with AI';
  }

  return `${action.charAt(0).toUpperCase()}${action.slice(1)} with AI`;
};

export const taskSchema = z.object({
  id: z.string().uuid(),
  title: nonEmptyTrimmedStringSchema,
  status: taskStatusSchema,
  parentTaskId: z.string().uuid().nullable(),
  sortOrder: z.number().int().nonnegative(),
  notes: z.string().nullable(),
  dueDate: taskDueDateSchema.nullable().default(null),
  proactivePlanningStatus: proactivePlanningStatusSchema
    .nullable()
    .default(null),
  proactiveSuggestionPending: z.boolean().default(false),
  proactiveSuggestionKind: z.enum(['execute', 'teach']).optional(),
  proactiveSuggestionLabel: z.string().nullable().default(null),
  proactiveOwnership: proactiveTaskOwnershipSchema.nullable().default(null),
  proactiveRequiredCapabilities: z.string().array().default([]),
  proactivePlanningConfidence: z
    .number()
    .min(0)
    .max(1)
    .nullable()
    .default(null),
  proactivePlanningRationale: z.string().nullable().default(null),
  proactiveQuestion: proactiveTaskQuestionSchema.nullable().default(null),
  proactiveAssignedAgentId: z.string().uuid().nullable().default(null),
  proactiveExecutionStatus: proactiveExecutionStatusSchema
    .nullable()
    .default(null),
  proactiveRetryCount: z.number().int().nonnegative().default(0),
  proactiveEvaluationKey: z.string().nullable().default(null),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
  completedAt: z.string().datetime().nullable(),
  deletedAt: z.string().datetime().nullable()
});

export type Task = z.infer<typeof taskSchema>;

export type TaskTree = Task & {
  children: TaskTree[];
};

export const taskTreeSchema: z.ZodType<TaskTree> = taskSchema.extend({
  children: z.lazy(() => taskTreeSchema.array())
});

export const createTaskInputSchema = z.object({
  title: nonEmptyTrimmedStringSchema,
  parentTaskId: z.string().uuid().nullable().optional(),
  notes: z.string().nullable().optional(),
  dueDate: taskDueDateSchema.nullable().optional()
});

export type CreateTaskInput = z.infer<typeof createTaskInputSchema>;

export const maxTaskScreenshotBytes = 5 * 1024 * 1024;

export const maxTaskListCharacters = 20_000;

export const taskTextImportInputSchema = z.object({
  text: z.string().trim().min(1).max(maxTaskListCharacters)
});

export type TaskTextImportInput = z.infer<typeof taskTextImportInputSchema>;

const base64ByteLength = (value: string): number =>
  Math.floor((value.length * 3) / 4) -
  (value.endsWith('==') ? 2 : value.endsWith('=') ? 1 : 0);

export const taskScreenshotImportInputSchema = z.object({
  name: nonEmptyTrimmedStringSchema,
  mimeType: z.enum(['image/png', 'image/jpeg', 'image/webp']),
  base64: z
    .string()
    .min(1)
    .regex(/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/)
    .refine((value) => base64ByteLength(value) <= maxTaskScreenshotBytes, {
      message: 'Screenshot must be 5 MB or smaller.'
    })
});

export type TaskScreenshotImportInput = z.infer<
  typeof taskScreenshotImportInputSchema
>;

export const reorderTasksInputSchema = z
  .object({
    parentTaskId: z.string().uuid().nullable(),
    taskIds: z.string().uuid().array().min(1)
  })
  .refine((value) => new Set(value.taskIds).size === value.taskIds.length, {
    message: 'Task IDs must be unique.',
    path: ['taskIds']
  });

export type ReorderTasksInput = z.infer<typeof reorderTasksInputSchema>;

export const updateTaskPatchSchema = z
  .object({
    title: nonEmptyTrimmedStringSchema.optional(),
    status: taskStatusSchema.optional(),
    notes: z.string().nullable().optional(),
    dueDate: taskDueDateSchema.nullable().optional(),
    proactiveAssignedAgentId: z.string().uuid().optional()
  })
  .refine((value) => Object.keys(value).length > 0, {
    message: 'Update patch cannot be empty.'
  });

export type UpdateTaskPatch = z.infer<typeof updateTaskPatchSchema>;
