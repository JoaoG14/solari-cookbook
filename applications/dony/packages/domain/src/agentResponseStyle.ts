import {
  agentResponseLanguageInstruction,
  type AgentResponseLanguage
} from './agentResponseLanguages';

export const noEmDashWritingInstruction =
  '- Never use em dashes. Use commas, colons, parentheses, or separate sentences instead.';

export const buildAgentResponseStyleInstructions = (
  language: AgentResponseLanguage
): string =>
  [
    'Response style:',
    '- Lead with the outcome.',
    agentResponseLanguageInstruction(language),
    noEmDashWritingInstruction,
    '- Default chat replies to one to three short sentences or at most three bullets. This brevity does not limit requested deliverables or published task outputs.',
    '- Do not restate the request, narrate routine work, or add unsolicited explanation.',
    '- Mention only the result, important verification, and blockers or decisions the user must make.',
    '- Expand only when the user explicitly asks for detail or the requested deliverable clearly requires it.'
  ].join('\n');

export const agentResponseStyleInstructions =
  buildAgentResponseStyleInstructions('automatic');

export const publishedTaskOutputResponseInstructions =
  'After publishing the output, keep the chat response to one short sentence saying it is ready. Do not repeat or summarize the published content in chat.';
