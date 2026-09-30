import type { ConnectorToolkitStatus } from './connectors';

export type ConnectorDisplayMetadata = {
  name: string;
  description: string;
  group: string;
  order: number;
  color: string;
};

const knownConnectors: Record<string, ConnectorDisplayMetadata> = {
  gmail: {
    name: 'Gmail',
    description: 'Search, read, and draft email from Gmail.',
    group: 'Google Workspace',
    order: 0,
    color: '#EA4335'
  },
  googlecalendar: {
    name: 'Google Calendar',
    description: 'Search events and availability in your calendar.',
    group: 'Google Workspace',
    order: 1,
    color: '#4285F4'
  },
  googledrive: {
    name: 'Google Drive',
    description: 'Search and manage files in Google Drive.',
    group: 'Google Workspace',
    order: 2,
    color: '#F9AB00'
  },
  googledocs: {
    name: 'Google Docs',
    description: 'Read, create, and edit Google Docs.',
    group: 'Google Workspace',
    order: 3,
    color: '#4285F4'
  },
  googlesheets: {
    name: 'Google Sheets',
    description: 'Read, create, and edit Google Sheets.',
    group: 'Google Workspace',
    order: 4,
    color: '#34A853'
  },
  googleslides: {
    name: 'Google Slides',
    description: 'Read, create, and edit Google Slides.',
    group: 'Google Workspace',
    order: 5,
    color: '#FBBC04'
  },
  outlook: {
    name: 'Outlook',
    description: 'Search email and manage Outlook calendar events.',
    group: 'Microsoft',
    order: 0,
    color: '#0078D4'
  },
  excel: {
    name: 'Microsoft Excel',
    description: 'Read, create, and edit Excel spreadsheets.',
    group: 'Microsoft',
    order: 1,
    color: '#217346'
  },
  microsoft_teams: {
    name: 'Microsoft Teams',
    description: 'Search conversations and collaborate in Microsoft Teams.',
    group: 'Microsoft',
    order: 2,
    color: '#6264A7'
  },
  slack: {
    name: 'Slack',
    description: 'Search conversations and collaborate in Slack.',
    group: 'Work',
    order: 0,
    color: '#4A154B'
  },
  asana: {
    name: 'Asana',
    description: 'Turn chats into actions.',
    group: 'Work',
    order: 1,
    color: '#F06A6A'
  },
  airtable: {
    name: 'Airtable',
    description: 'Read, create, and update Airtable records.',
    group: 'Work',
    order: 2,
    color: '#18BFFF'
  },
  confluence: {
    name: 'Confluence',
    description: 'Search, create, and edit Confluence knowledge.',
    group: 'Work',
    order: 3,
    color: '#1868DB'
  },
  zoom: {
    name: 'Zoom',
    description: 'Manage Zoom meetings and recordings.',
    group: 'Work',
    order: 4,
    color: '#0B5CFF'
  },
  canva: {
    name: 'Canva',
    description: 'Search, create, and edit designs.',
    group: 'Design',
    order: 0,
    color: '#7D2AE8'
  },
  cloudflare: {
    name: 'Cloudflare',
    description: 'Manage Cloudflare infrastructure and services.',
    group: 'Developer tools',
    order: 0,
    color: '#F38020'
  },
  figma: {
    name: 'Figma',
    description: 'Inspect designs and support design-to-code workflows.',
    group: 'Design',
    order: 1,
    color: '#A259FF'
  },
  granola_mcp: {
    name: 'Granola',
    description: 'Add meeting notes, transcripts, and context.',
    group: 'Work',
    order: 5,
    color: '#E7A45B'
  },
  hugging_face: {
    name: 'Hugging Face',
    description: 'Inspect models, datasets, Spaces, and research.',
    group: 'Developer tools',
    order: 1,
    color: '#FFD21E'
  },
  linear: {
    name: 'Linear',
    description: 'Plan and build products.',
    group: 'Work',
    order: 6,
    color: '#5E6AD2'
  },
  notion: {
    name: 'Notion',
    description: 'Work with specs, research, meetings, and knowledge.',
    group: 'Work',
    order: 7,
    color: '#555550'
  },
  render: {
    name: 'Render',
    description: 'Deploy, debug, monitor, and migrate apps.',
    group: 'Developer tools',
    order: 2,
    color: '#46E3B7'
  },
  stripe: {
    name: 'Stripe',
    description: 'Manage payments and Stripe resources.',
    group: 'Business',
    order: 0,
    color: '#635BFF'
  },
  supabase: {
    name: 'Supabase',
    description: 'Manage and query databases.',
    group: 'Developer tools',
    order: 3,
    color: '#3ECF8E'
  },
  vercel: {
    name: 'Vercel',
    description: 'Search docs and manage deployments.',
    group: 'Developer tools',
    order: 4,
    color: '#333330'
  }
};

export const connectorDisplayMetadata = (
  toolkit: ConnectorToolkitStatus
): ConnectorDisplayMetadata => {
  const metadata = knownConnectors[toolkit.slug.toLowerCase()];

  return (
    metadata ?? {
      name: toolkit.name,
      description: toolkit.status,
      group: 'Connectors',
      order: 1000,
      color: '#6E6E68'
    }
  );
};

const connectorDisplayPriority = (toolkit: ConnectorToolkitStatus): number => {
  const metadata = connectorDisplayMetadata(toolkit);

  if (metadata.group === 'Google Workspace') {
    return 0;
  }

  switch (toolkit.slug.toLowerCase()) {
    case 'notion':
      return 1;
    case 'canva':
      return 2;
    case 'figma':
      return 3;
    case 'stripe':
      return 4;
    default:
      return 5;
  }
};

export const sortConnectorToolkits = (
  toolkits: ConnectorToolkitStatus[]
): ConnectorToolkitStatus[] =>
  [...toolkits].sort((left, right) => {
    const leftMetadata = connectorDisplayMetadata(left);
    const rightMetadata = connectorDisplayMetadata(right);

    return (
      connectorDisplayPriority(left) - connectorDisplayPriority(right) ||
      leftMetadata.group.localeCompare(rightMetadata.group) ||
      leftMetadata.order - rightMetadata.order ||
      leftMetadata.name.localeCompare(rightMetadata.name)
    );
  });
