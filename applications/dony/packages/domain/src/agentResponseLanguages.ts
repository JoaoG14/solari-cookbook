import { z } from 'zod';

export const agentResponseLanguageSchema = z.enum([
  'automatic',
  'en',
  'pt-BR',
  'es',
  'fr',
  'de',
  'it',
  'ja',
  'ko',
  'zh-CN'
]);

export type AgentResponseLanguage = z.infer<typeof agentResponseLanguageSchema>;

export const agentResponseLanguageOptions: ReadonlyArray<{
  value: AgentResponseLanguage;
  label: string;
}> = [
  { value: 'automatic', label: 'Automatic' },
  { value: 'en', label: 'English' },
  { value: 'pt-BR', label: 'Portuguese (Brazil)' },
  { value: 'es', label: 'Spanish' },
  { value: 'fr', label: 'French' },
  { value: 'de', label: 'German' },
  { value: 'it', label: 'Italian' },
  { value: 'ja', label: 'Japanese' },
  { value: 'ko', label: 'Korean' },
  { value: 'zh-CN', label: 'Chinese (Simplified)' }
];

const fixedLanguageNames: Record<
  Exclude<AgentResponseLanguage, 'automatic'>,
  string
> = {
  en: 'English',
  'pt-BR': 'Brazilian Portuguese',
  es: 'Spanish',
  fr: 'French',
  de: 'German',
  it: 'Italian',
  ja: 'Japanese',
  ko: 'Korean',
  'zh-CN': 'Simplified Chinese'
};

export const agentResponseLanguageInstruction = (
  language: AgentResponseLanguage
): string => {
  if (language === 'automatic') {
    return '- Match the language of the latest user request. Use another language only when the user explicitly asks for it.';
  }

  return `- Write the response in ${fixedLanguageNames[language]}, regardless of the language of the request. Use another language only when the user explicitly asks for it.`;
};
