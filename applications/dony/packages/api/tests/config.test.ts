import { afterEach, describe, expect, it, vi } from 'vitest';

const stubRequiredEnv = (): void => {
  vi.stubEnv('DATABASE_URL', 'postgres://dony:dony@127.0.0.1:5432/dony');
  vi.stubEnv('DONY_API_DEV_AUTH_TOKEN', 'dev-token');
  vi.stubEnv('DONY_COMPOSIO_API_KEY', 'composio-key');
};

const importConfig = async () => {
  vi.resetModules();
  return import('../src/config');
};

afterEach(() => {
  vi.unstubAllEnvs();
});

describe('config', () => {
  it('enables the supported Composio plugin defaults', async () => {
    stubRequiredEnv();

    const { config } = await importConfig();

    expect(config.composio).toEqual(
      expect.objectContaining({
        enabled: true,
        gmailToolkitVersion: '20260721_00',
        googleDriveToolkitVersion: '20260826_00',
        toolkits: [
          'gmail',
          'googlecalendar',
          'googledrive',
          'googledocs',
          'googlesheets',
          'googleslides',
          'outlook',
          'excel',
          'microsoft_teams',
          'slack',
          'asana',
          'airtable',
          'confluence',
          'zoom',
          'canva',
          'cloudflare',
          'figma',
          'granola_mcp',
          'hugging_face',
          'linear',
          'notion',
          'render',
          'stripe',
          'supabase',
          'vercel'
        ]
      })
    );
  });

  it('preserves explicit Composio toolkit overrides', async () => {
    stubRequiredEnv();
    vi.stubEnv('DONY_COMPOSIO_TOOLKITS', 'gmail,notion');
    vi.stubEnv('DONY_COMPOSIO_GMAIL_VERSION', '20260801_00');
    vi.stubEnv('DONY_COMPOSIO_GOOGLE_DRIVE_VERSION', '20260802_00');

    const { config } = await importConfig();

    expect(config.composio).toEqual(
      expect.objectContaining({
        enabled: true,
        gmailToolkitVersion: '20260801_00',
        googleDriveToolkitVersion: '20260802_00',
        toolkits: ['gmail', 'notion']
      })
    );
  });
});
