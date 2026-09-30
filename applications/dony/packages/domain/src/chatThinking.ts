import { z } from 'zod';

export const chatThinkingSchema = z.enum([
  'quick',
  'everyday',
  'balanced',
  'thorough',
  'deep'
]);
export type ChatThinking = z.infer<typeof chatThinkingSchema>;

export const chatThinkingEffort = {
  quick: 'low',
  everyday: 'low',
  balanced: 'medium',
  thorough: 'medium',
  deep: 'medium'
} as const;

const models: Record<ChatThinking, string> = {
  quick: 'gpt-6-luna',
  everyday: 'gpt-5.6-terra',
  balanced: 'gpt-5.6-terra',
  thorough: 'gpt-6-sol',
  deep: 'gpt-6-astra'
};

export function chatThinkingModel(
  thinking: ChatThinking,
  available: string[],
  fallback: string
): string {
  const prefix = fallback.includes('/') ? fallback.split('/')[0] + '/' : '';
  const selected = prefix + models[thinking];
  return available.includes(selected) ? selected : fallback;
}
