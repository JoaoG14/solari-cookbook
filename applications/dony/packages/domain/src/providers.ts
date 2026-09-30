import { z } from 'zod';

import {
  nonEmptyTrimmedStringSchema,
  nullableTrimmedStringSchema
} from './shared';

export const providerTypeSchema = z.enum([
  'dony_native',
  'codex_local',
  'claude_code_local',
  'gemini_cli_local',
  'hermes_local',
  'openclaw',
  'openrouter',
  'ollama'
]);

export type ProviderType = z.infer<typeof providerTypeSchema>;

export const providerStatusSchema = z.enum(['unknown', 'ready', 'error']);

export type ProviderStatus = z.infer<typeof providerStatusSchema>;

export const codexExecutionModeSchema = z.enum([
  'read_only',
  'workspace_write',
  'full_auto',
  'bypass_sandbox'
]);

export type CodexExecutionMode = z.infer<typeof codexExecutionModeSchema>;

export const modelEffortSchema = z.enum([
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
  'ultra'
]);

export type ModelEffort = z.infer<typeof modelEffortSchema>;

export const modelServiceTierSchema = z.enum(['default', 'priority']);

export type ModelServiceTier = z.infer<typeof modelServiceTierSchema>;

export const providerConnectionSchema = z.object({
  baseUrl: z.string().url().optional(),
  agentId: nonEmptyTrimmedStringSchema.optional(),
  sessionKey: nonEmptyTrimmedStringSchema.optional(),
  profile: nonEmptyTrimmedStringSchema.optional(),
  credentialId: z.string().uuid().optional()
});

export type ProviderConnection = z.infer<typeof providerConnectionSchema>;

export const additionalProviderTypes = [
  'gemini_cli_local',
  'hermes_local',
  'openclaw',
  'openrouter',
  'ollama'
] as const;
export type AdditionalProviderType = (typeof additionalProviderTypes)[number];
export const isAdditionalProvider = (
  type: ProviderType
): type is AdditionalProviderType =>
  additionalProviderTypes.some((provider) => provider === type);
export const isAcpProvider = (type: ProviderType): boolean =>
  type === 'gemini_cli_local' || type === 'hermes_local' || type === 'openclaw';

export const providerConfigSchema = z.object({
  id: z.string().uuid(),
  name: nonEmptyTrimmedStringSchema,
  providerType: providerTypeSchema,
  command: nonEmptyTrimmedStringSchema,
  connection: providerConnectionSchema.optional(),
  defaultModel: nullableTrimmedStringSchema,
  status: providerStatusSchema,
  lastCheckedAt: z.string().datetime().nullable(),
  lastError: z.string().nullable(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
  deletedAt: z.string().datetime().nullable()
});

export type ProviderConfig = z.infer<typeof providerConfigSchema>;

export const createProviderConfigInputSchema = z.object({
  name: nonEmptyTrimmedStringSchema,
  providerType: providerTypeSchema,
  command: nonEmptyTrimmedStringSchema,
  connection: providerConnectionSchema.optional(),
  defaultModel: nullableTrimmedStringSchema.optional(),
  status: providerStatusSchema.optional(),
  lastCheckedAt: z.string().datetime().nullable().optional(),
  lastError: z.string().nullable().optional()
});

export type CreateProviderConfigInput = z.infer<
  typeof createProviderConfigInputSchema
>;

export const updateProviderConfigPatchSchema = z
  .object({
    name: nonEmptyTrimmedStringSchema.optional(),
    providerType: providerTypeSchema.optional(),
    command: nonEmptyTrimmedStringSchema.optional(),
    connection: providerConnectionSchema.optional(),
    defaultModel: nullableTrimmedStringSchema.optional(),
    status: providerStatusSchema.optional(),
    lastCheckedAt: z.string().datetime().nullable().optional(),
    lastError: z.string().nullable().optional(),
    deletedAt: z.string().datetime().nullable().optional()
  })
  .refine((value) => Object.keys(value).length > 0, {
    message: 'Update patch cannot be empty.'
  });

export type UpdateProviderConfigPatch = z.infer<
  typeof updateProviderConfigPatchSchema
>;

export const providerConfigDraftSchema = z.object({
  name: nonEmptyTrimmedStringSchema,
  providerType: providerTypeSchema,
  command: nonEmptyTrimmedStringSchema,
  connection: providerConnectionSchema.optional(),
  defaultModel: nullableTrimmedStringSchema
});

export type ProviderConfigDraft = z.infer<typeof providerConfigDraftSchema>;

export const providerConnectionCheckSchema = z.object({
  providerType: providerTypeSchema,
  command: nonEmptyTrimmedStringSchema,
  connection: providerConnectionSchema.optional(),
  status: providerStatusSchema,
  lastCheckedAt: z.string().datetime(),
  lastError: z.string().nullable()
});

export type ProviderConnectionCheck = z.infer<
  typeof providerConnectionCheckSchema
>;

export const providerConfigDefaultsSchema = z.object({
  providerType: providerTypeSchema,
  command: nonEmptyTrimmedStringSchema,
  connection: providerConnectionSchema.optional(),
  defaultModel: nullableTrimmedStringSchema
});

export type ProviderConfigDefaults = z.infer<
  typeof providerConfigDefaultsSchema
>;

export const providerCatalog = [
  {
    type: 'dony_native',
    label: 'Dony',
    description: 'Native Dony agent',
    isEnabled: true
  },
  {
    type: 'codex_local',
    label: 'ChatGPT',
    description: 'Use your ChatGPT plan',
    isEnabled: true
  },
  {
    type: 'claude_code_local',
    label: 'Claude Code',
    description: 'Local Claude Code CLI',
    isEnabled: true
  },
  {
    type: 'gemini_cli_local',
    label: 'Gemini CLI',
    description: 'Use your Gemini CLI account',
    isEnabled: true
  },
  {
    type: 'hermes_local',
    label: 'Hermes Agent',
    description: 'Use your existing Hermes memory and skills',
    isEnabled: true
  },
  {
    type: 'openclaw',
    label: 'OpenClaw',
    description: 'Connect your existing assistant and gateway',
    isEnabled: true
  },
  {
    type: 'openrouter',
    label: 'Dony · OpenRouter',
    description: 'Dony agent with your OpenRouter models',
    isEnabled: true
  },
  {
    type: 'ollama',
    label: 'Dony · Ollama',
    description: 'Dony agent with local Ollama models',
    isEnabled: true
  }
] as const satisfies ReadonlyArray<{
  type: ProviderType;
  label: string;
  description: string;
  isEnabled: boolean;
}>;

export const providerLabelByType = Object.fromEntries(
  providerCatalog.map((provider) => [provider.type, provider.label])
) as Record<ProviderType, string>;

export const codexExecutionModeLabels = {
  read_only: 'Read-only',
  workspace_write: 'Workspace write',
  full_auto: 'Full auto',
  bypass_sandbox: 'Bypass sandbox'
} as const satisfies Record<CodexExecutionMode, string>;

export const codexExecutionModeDescriptions = {
  read_only: 'Inspect and answer without editing files.',
  workspace_write: 'Edit files inside the selected workspace sandbox.',
  full_auto: 'Run with full local access and no provider permission prompts.',
  bypass_sandbox: 'Run without provider permission safeguards.'
} as const satisfies Record<CodexExecutionMode, string>;

export const providerModelOptionSchema = z.object({
  value: nonEmptyTrimmedStringSchema,
  label: nonEmptyTrimmedStringSchema,
  badge: z.string().optional(),
  effortLevels: modelEffortSchema.array(),
  serviceTiers: z.literal('priority').array().optional()
});

export type ProviderModelOption = z.infer<typeof providerModelOptionSchema>;

export type ProviderEffortOption = {
  value: ModelEffort;
  label: string;
};

export const modelEffortOptions = [
  { value: 'low', label: 'Low' },
  { value: 'medium', label: 'Medium' },
  { value: 'high', label: 'High' },
  { value: 'xhigh', label: 'Extra high' },
  { value: 'max', label: 'Max' },
  { value: 'ultra', label: 'Ultra' }
] as const satisfies ReadonlyArray<ProviderEffortOption>;

export const modelEffortLabelByValue = Object.fromEntries(
  modelEffortOptions.map((option) => [option.value, option.label])
) as Record<ModelEffort, string>;

export const providerModelOptions: Record<ProviderType, ProviderModelOption[]> = {
  gemini_cli_local: [],
  hermes_local: [],
  openclaw: [],
  openrouter: [],
  ollama: [],
  dony_native: [
    {
      value: 'dony-auto',
      label: 'Dony Auto',
      effortLevels: []
    }
  ],
  codex_local: [
    {
      value: 'gpt-5.6-sol',
      label: 'GPT-5.6 Sol',
      effortLevels: ['low', 'medium', 'high', 'xhigh', 'max', 'ultra'],
      serviceTiers: ['priority']
    },
    {
      value: 'gpt-5.6-terra',
      label: 'GPT-5.6 Terra',
      effortLevels: ['low', 'medium', 'high', 'xhigh', 'max', 'ultra'],
      serviceTiers: ['priority']
    },
    {
      value: 'gpt-5.6-luna',
      label: 'GPT-5.6 Luna',
      effortLevels: ['low', 'medium', 'high', 'xhigh', 'max'],
      serviceTiers: ['priority']
    },
    {
      value: 'gpt-5.5',
      label: 'GPT-5.5',
      effortLevels: ['low', 'medium', 'high', 'xhigh'],
      serviceTiers: ['priority']
    },
    {
      value: 'gpt-5.4',
      label: 'GPT-5.4',
      effortLevels: ['low', 'medium', 'high', 'xhigh'],
      serviceTiers: ['priority']
    },
    {
      value: 'gpt-5.4-mini',
      label: 'GPT-5.4 Mini',
      effortLevels: ['low', 'medium', 'high', 'xhigh']
    },
    {
      value: 'gpt-5.3-codex-spark',
      label: 'GPT-5.3-Codex-Spark',
      effortLevels: ['low', 'medium', 'high', 'xhigh']
    }
  ],
  claude_code_local: [
    {
      value: 'claude-opus-4-7[1m]',
      label: 'Opus 4.7 1M',
      badge: 'NEW',
      effortLevels: ['low', 'medium', 'high', 'xhigh', 'max']
    },
    {
      value: 'claude-opus-4-7',
      label: 'Opus 4.7',
      badge: 'NEW',
      effortLevels: ['low', 'medium', 'high', 'xhigh', 'max']
    },
    {
      value: 'claude-opus-4-6[1m]',
      label: 'Opus 4.6 1M',
      effortLevels: ['low', 'medium', 'high', 'max']
    },
    {
      value: 'claude-sonnet-4-6',
      label: 'Sonnet 4.6',
      effortLevels: ['low', 'medium', 'high', 'max']
    },
    {
      value: 'claude-haiku-4-5-20251001',
      label: 'Haiku 4.5',
      effortLevels: []
    }
  ]
};

export const providerDefaultModelByType: Record<ProviderType, string> = {
  gemini_cli_local: '',
  hermes_local: '',
  openclaw: '',
  openrouter: '',
  ollama: '',
  dony_native: 'dony-auto',
  codex_local: 'gpt-5.6-terra',
  claude_code_local: 'claude-opus-4-7[1m]'
};

const modelLabelByValue = Object.fromEntries(
  Object.values(providerModelOptions)
    .flat()
    .map((option) => [option.value, option.label])
) as Record<string, string>;

const modelOptionsForProvider = (
  providerType: ProviderType,
  modelOptions?: ProviderModelOption[]
): ProviderModelOption[] => modelOptions ?? providerModelOptions[providerType];

export const getModelOption = (
  providerType: ProviderType,
  model: string,
  modelOptions?: ProviderModelOption[]
): ProviderModelOption | null =>
  modelOptionsForProvider(providerType, modelOptions).find(
    (option) => option.value === model
  ) ??
  null;

export const getProviderModelOptionsWithCustomValue = (
  providerType: ProviderType,
  value: string,
  modelOptions?: ProviderModelOption[]
): ProviderModelOption[] => {
  const baseOptions = modelOptionsForProvider(providerType, modelOptions);
  const normalizedValue = value.trim();

  if (
    normalizedValue.length === 0 ||
    baseOptions.some((option) => option.value === normalizedValue)
  ) {
    return baseOptions;
  }

  return [
    {
      value: normalizedValue,
      label: formatModelLabel(normalizedValue),
      effortLevels: []
    },
    ...baseOptions
  ];
};

export const getEffortOptionsForModel = (
  providerType: ProviderType,
  model: string,
  modelOptions?: ProviderModelOption[]
): ProviderEffortOption[] => {
  const effortLevels =
    getModelOption(providerType, model, modelOptions)?.effortLevels ?? [];

  return modelEffortOptions.filter((option) =>
    effortLevels.includes(option.value)
  );
};

export const getDefaultModelEffort = (
  providerType: ProviderType,
  model: string | null,
  modelOptions?: ProviderModelOption[]
): ModelEffort | null => {
  if (providerType === 'codex_local' && model === null) {
    return 'medium';
  }

  if (!model) {
    return null;
  }

  const effortLevels =
    getModelOption(providerType, model, modelOptions)?.effortLevels ?? [];

  if (effortLevels.length === 0) {
    return null;
  }

  if (providerType === 'codex_local') {
    return effortLevels.includes('medium')
      ? 'medium'
      : (effortLevels[0] ?? null);
  }

  if (model.includes('opus-4-7')) {
    return 'xhigh';
  }

  const firstEffort = effortLevels[0];

  if (!firstEffort) {
    throw new Error(`Expected default effort for model: ${model}`);
  }

  return effortLevels.includes('high') ? 'high' : firstEffort;
};

export const normalizeModelEffort = (
  providerType: ProviderType,
  model: string | null,
  effort: ModelEffort | null,
  modelOptions?: ProviderModelOption[]
): ModelEffort | null => {
  const effortLevels =
    model === null
      ? []
      : (getModelOption(providerType, model, modelOptions)?.effortLevels ?? []);

  if (providerType === 'codex_local' && model === null) {
    return getDefaultModelEffort(providerType, model, modelOptions);
  }

  if (effortLevels.length === 0) {
    return providerType === 'codex_local' ? effort : null;
  }

  if (effort && effortLevels.includes(effort)) {
    return effort;
  }

  return getDefaultModelEffort(providerType, model, modelOptions);
};

export const formatModelLabel = (model: string): string =>
  modelLabelByValue[model] ?? model;
