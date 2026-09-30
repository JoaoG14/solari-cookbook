import { expect, it } from 'vitest';
import { chatThinkingEffort, chatThinkingModel, chatThinkingSchema } from './chatThinking';
import { companionCommandSchema } from './companion';

it.each([
  ['quick', 'gpt-6-luna', 'low'],
  ['everyday', 'gpt-5.6-terra', 'low'],
  ['balanced', 'gpt-5.6-terra', 'medium'],
  ['thorough', 'gpt-6-sol', 'medium'],
  ['deep', 'gpt-6-astra', 'medium']
] as const)('maps %s to exactly %s at %s effort', (thinking, model, effort) => {
  const models = ['gpt-5.6-luna', 'gpt-5.6-terra', 'gpt-5.6-sol',
    'gpt-6-luna', 'gpt-6-sol', 'gpt-6-astra', 'o4-mini-high'];
  expect(chatThinkingModel(thinking, models, 'gpt-5.6-terra')).toBe(model);
  expect(chatThinkingModel(thinking, models.map(id => `openai/${id}`), 'openai/gpt-5.4-mini')).toBe(`openai/${model}`);
  expect(chatThinkingEffort[thinking]).toBe(effort);
  expect(chatThinkingModel(thinking, [], 'custom/model')).toBe('custom/model');
});

it('accepts every mobile thinking choice and keeps older commands compatible', () => {
  const command = {
    id: '00000000-0000-4000-8000-000000000001',
    action: {
      type: 'chat.send',
      threadId: '00000000-0000-4000-8000-000000000002',
      message: 'Help'
    }
  };
  expect(companionCommandSchema.parse(command).action).not.toHaveProperty(
    'thinking'
  );
  for (const thinking of chatThinkingSchema.options) {
    expect(
      companionCommandSchema.parse({
        ...command,
        action: { ...command.action, thinking }
      }).action
    ).toHaveProperty('thinking', thinking);
  }
  expect(
    companionCommandSchema.safeParse({
      ...command,
      action: { ...command.action, thinking: 'unsupported' }
    }).success
  ).toBe(false);
});
