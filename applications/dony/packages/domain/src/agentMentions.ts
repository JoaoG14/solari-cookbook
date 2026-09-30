import type { Agent } from './agents';

const agentTagPattern = /(?:^|\s)@([a-zA-Z0-9_-]+)/g;

export const normalizeAgentTag = (value: string): string =>
  value.toLowerCase().replace(/[^a-z0-9]/g, '');

export const extractAgentTags = (value: string): string[] => {
  const tags = new Set<string>();

  for (const match of value.matchAll(agentTagPattern)) {
    const tag = match[1];

    if (!tag) {
      continue;
    }

    const normalizedTag = normalizeAgentTag(tag);

    if (normalizedTag.length > 0) {
      tags.add(normalizedTag);
    }
  }

  return [...tags];
};

export const agentMatchesTag = (agent: Agent, tag: string): boolean =>
  normalizeAgentTag(agent.name) === normalizeAgentTag(tag);

export const toAgentNameTag = (agent: Agent): string => {
  const slug = agent.name
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');

  return `@${slug}`;
};
