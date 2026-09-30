import { z } from 'zod';

import { nonEmptyTrimmedStringSchema } from './shared';

export const taskOutputKindSchema = z.enum([
  'summary',
  'brief',
  'report',
  'analysis',
  'comparison',
  'plan',
  'itinerary',
  'output'
]);

export type TaskOutputKind = z.infer<typeof taskOutputKindSchema>;

export const taskResultFileArtifactSchema = z.object({
  type: z.literal('file'),
  path: nonEmptyTrimmedStringSchema,
  label: nonEmptyTrimmedStringSchema.nullable().optional()
});

export type TaskResultFileArtifact = z.infer<
  typeof taskResultFileArtifactSchema
>;

export const taskResultLinkUrlSchema = z
  .string()
  .url()
  .refine((value) => {
    try {
      const url = new URL(value);

      return (
        url.protocol === 'https:' &&
        url.hostname === 'docs.google.com' &&
        url.pathname.startsWith('/presentation/d/')
      );
    } catch {
      return false;
    }
  });

export const taskResultLinkArtifactSchema = z.object({
  type: z.literal('link'),
  url: taskResultLinkUrlSchema,
  kind: z.literal('slides'),
  title: nonEmptyTrimmedStringSchema
});

export type TaskResultLinkArtifact = z.infer<
  typeof taskResultLinkArtifactSchema
>;

export const taskResultOutputArtifactSchema = z.object({
  type: z.literal('task_output'),
  outputId: z.string().uuid(),
  kind: taskOutputKindSchema,
  title: nonEmptyTrimmedStringSchema
});

export const taskResultArtifactSchema = z.discriminatedUnion('type', [
  taskResultFileArtifactSchema,
  taskResultLinkArtifactSchema,
  taskResultOutputArtifactSchema
]);

export type TaskResultArtifact = z.infer<typeof taskResultArtifactSchema>;

export type TaskResultOutputArtifact = z.infer<
  typeof taskResultOutputArtifactSchema
>;

const fileCitationPattern = /:{1,3}codex-file-citation\{([^}\r\n]*)\}/giu;
const fileCitationAttributePattern =
  /([a-z][a-z0-9_-]*)="((?:\\.|[^"\\])*)"/giu;
const googleSlidesMarkdownLinkPattern =
  /\[([^\]\r\n]+)\]\((https:\/\/docs\.google\.com\/presentation\/d\/[^)\s]+)\)/giu;

const decodeDirectiveAttribute = (value: string): string => {
  try {
    return JSON.parse(`"${value}"`) as string;
  } catch {
    return value;
  }
};

const parseFileCitationAttributes = (value: string): Record<string, string> => {
  const attributes: Record<string, string> = {};

  for (const match of value.matchAll(fileCitationAttributePattern)) {
    const name = match[1];
    const attributeValue = match[2];

    if (name && attributeValue !== undefined) {
      attributes[name] = decodeDirectiveAttribute(attributeValue);
    }
  }

  return attributes;
};

export const extractTaskResultFileArtifacts = (
  value: string
): { content: string; artifacts: TaskResultFileArtifact[] } => {
  const artifacts = new Map<string, TaskResultFileArtifact>();
  const content = value.replace(
    fileCitationPattern,
    (directive, rawAttributes: string) => {
      const attributes = parseFileCitationAttributes(rawAttributes);
      const path = attributes.path?.trim();

      if (!path || attributes.purpose === 'source') {
        return directive;
      }

      artifacts.set(path, {
        type: 'file',
        path,
        label: path.split(/[\\/]/u).filter(Boolean).at(-1) ?? path
      });

      return '';
    }
  );

  return {
    content: content
      .replace(/[ \t]{2,}/gu, ' ')
      .replace(/[ \t]+([,.;!?])/gu, '$1')
      .replace(/:\s*([.!?])/gu, '$1')
      .replace(/[ \t]+\n/gu, '\n')
      .replace(/\n{3,}/gu, '\n\n')
      .trim(),
    artifacts: [...artifacts.values()]
  };
};

export const extractTaskResultArtifacts = (
  value: string
): { content: string; artifacts: TaskResultArtifact[] } => {
  const fileResult = extractTaskResultFileArtifacts(value);
  const links = new Map<string, TaskResultLinkArtifact>();
  const content = fileResult.content.replace(
    googleSlidesMarkdownLinkPattern,
    (_link, rawTitle: string, rawUrl: string) => {
      const title = rawTitle.trim();
      const parsed = taskResultLinkArtifactSchema.safeParse({
        type: 'link',
        url: rawUrl,
        kind: 'slides',
        title
      });

      if (!parsed.success) {
        return _link;
      }

      links.set(parsed.data.url, parsed.data);
      return title;
    }
  );

  return {
    content,
    artifacts: [...fileResult.artifacts, ...links.values()]
  };
};

export const publishTaskOutputInputSchema = z.object({
  kind: taskOutputKindSchema,
  title: nonEmptyTrimmedStringSchema.max(160),
  html: z.string().min(1).max(2_000_000)
});

export type PublishTaskOutputInput = z.infer<
  typeof publishTaskOutputInputSchema
>;

export const homeTaskAgentResultSchema = z.object({
  id: z.string().uuid(),
  taskId: z.string().uuid(),
  runId: z.string().uuid(),
  threadId: z.string().uuid(),
  agentId: z.string().uuid(),
  assistantMessageId: z.string().uuid(),
  taskTitle: nonEmptyTrimmedStringSchema,
  agentName: nonEmptyTrimmedStringSchema,
  agentEmoji: nonEmptyTrimmedStringSchema,
  agentColor: nonEmptyTrimmedStringSchema,
  providerLabel: nonEmptyTrimmedStringSchema,
  threadTitle: nonEmptyTrimmedStringSchema,
  preview: z.string(),
  outcome: z
    .enum(['completed', 'review', 'blocked', 'failed'])
    .nullable()
    .default(null),
  artifacts: taskResultArtifactSchema.array(),
  completedAt: z.string().datetime(),
  dismissedAt: z.string().datetime().nullable(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime()
});

export type HomeTaskAgentResult = z.infer<typeof homeTaskAgentResultSchema>;

export const proactiveTaskOutcomeSchema = z.enum([
  'completed',
  'review',
  'blocked',
  'failed'
]);

export type ProactiveTaskOutcome = z.infer<typeof proactiveTaskOutcomeSchema>;

const proactiveTaskOutcomePattern =
  /(?:^|\n)DONY_TASK_OUTCOME:\s*(completed|review|blocked|failed)\s*$/iu;

export const taskCompletionOutcomeInstructions = [
  'Use review when the requested work is finished so the user can confirm it with Looks good.',
  'Never mark the task completed yourself.',
  'Use blocked when you need user input before the work can continue.',
  'Use failed when the work could not be completed.',
  'End your final response with exactly one of these lines:',
  'DONY_TASK_OUTCOME: review',
  'DONY_TASK_OUTCOME: blocked',
  'DONY_TASK_OUTCOME: failed'
] as const;

export const proactiveTaskOutcomeFromText = (
  value: string
): ProactiveTaskOutcome | null => {
  const match = proactiveTaskOutcomePattern.exec(value.trim());
  return match?.[1]
    ? proactiveTaskOutcomeSchema.parse(match[1].toLowerCase())
    : null;
};

export const stripProactiveTaskOutcome = (value: string): string =>
  value.replace(proactiveTaskOutcomePattern, '').trim();
