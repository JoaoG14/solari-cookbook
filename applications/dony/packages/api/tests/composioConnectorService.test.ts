import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const composio = vi.hoisted(() => ({
  create: vi.fn(),
  files: {
    upload: vi.fn()
  },
  connectedAccounts: {
    list: vi.fn(),
    refresh: vi.fn(),
    enable: vi.fn(),
    disable: vi.fn(),
    delete: vi.fn()
  }
}));

vi.mock('@composio/core', () => ({
  Composio: class {
    public readonly connectedAccounts = composio.connectedAccounts;
    public readonly create = composio.create;
    public readonly files = composio.files;
  }
}));

const connectedAccount = (overrides: Record<string, unknown> = {}) => ({
  id: 'ca_gmail',
  toolkit: { slug: 'gmail' },
  authConfig: { id: 'ac_gmail' },
  status: 'ACTIVE',
  updatedAt: '2026-08-16T12:00:00.000Z',
  ...overrides
});

describe('ComposioConnectorService account lifecycle', () => {
  let ComposioConnectorService: typeof import('../src/composioConnectorService').ComposioConnectorService;

  beforeEach(async () => {
    vi.resetModules();
    vi.stubEnv('DATABASE_URL', 'postgres://dony:test@127.0.0.1:5432/dony');
    vi.stubEnv('DONY_API_DEV_AUTH_TOKEN', 'test-auth-token');
    vi.stubEnv('DONY_COMPOSIO_API_KEY', 'test-composio-key');
    vi.stubEnv('DONY_COMPOSIO_TOOLKITS', 'gmail');

    composio.create.mockReset();
    composio.files.upload.mockReset();
    Object.values(composio.connectedAccounts).forEach((mock) =>
      mock.mockReset()
    );

    ({ ComposioConnectorService } =
      await import('../src/composioConnectorService'));
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it('keeps an inactive owned account manageable in the toolkit list', async () => {
    composio.create.mockResolvedValue({
      toolkits: vi.fn().mockResolvedValue({
        items: [
          {
            slug: 'gmail',
            name: 'Gmail',
            logo: 'https://logos.composio.dev/api/gmail',
            connection: { isActive: false, connectedAccount: null }
          }
        ]
      })
    });
    composio.connectedAccounts.list.mockResolvedValue({
      items: [connectedAccount({ status: 'INACTIVE' })],
      nextCursor: null
    });

    const service = new ComposioConnectorService();

    await expect(service.list('user_123')).resolves.toEqual(
      expect.objectContaining({
        toolkits: [
          expect.objectContaining({
            slug: 'gmail',
            isConnected: false,
            status: 'INACTIVE',
            connectedAccountId: 'ca_gmail',
            authConfigId: 'ac_gmail'
          })
        ]
      })
    );
    expect(composio.connectedAccounts.list).toHaveBeenCalledWith({
      userIds: ['user_123'],
      toolkitSlugs: ['gmail'],
      cursor: undefined,
      limit: 100
    });
  });

  it('checks paginated ownership before refreshing an account', async () => {
    composio.connectedAccounts.list
      .mockResolvedValueOnce({
        items: [connectedAccount({ id: 'ca_other' })],
        nextCursor: 'next-page'
      })
      .mockResolvedValueOnce({
        items: [connectedAccount()],
        nextCursor: null
      });
    composio.connectedAccounts.refresh.mockResolvedValue({
      redirect_url: 'https://connect.composio.dev/refresh'
    });

    const service = new ComposioConnectorService();

    await expect(service.refresh('user_123', 'ca_gmail')).resolves.toBe(
      'https://connect.composio.dev/refresh'
    );
    expect(composio.connectedAccounts.refresh).toHaveBeenCalledWith('ca_gmail');
  });

  it('supports pause, resume, and permanent disconnect for an owned account', async () => {
    composio.connectedAccounts.list.mockResolvedValue({
      items: [connectedAccount()],
      nextCursor: null
    });
    composio.connectedAccounts.disable.mockResolvedValue({ success: true });
    composio.connectedAccounts.enable.mockResolvedValue({ success: true });
    composio.connectedAccounts.delete.mockResolvedValue({ success: true });

    const service = new ComposioConnectorService();

    await service.setEnabled('user_123', 'ca_gmail', false);
    await service.setEnabled('user_123', 'ca_gmail', true);
    await service.disconnect('user_123', 'ca_gmail');

    expect(composio.connectedAccounts.disable).toHaveBeenCalledWith('ca_gmail');
    expect(composio.connectedAccounts.enable).toHaveBeenCalledWith('ca_gmail');
    expect(composio.connectedAccounts.delete).toHaveBeenCalledWith('ca_gmail');
  });

  it('disconnects every owned account when the Dony account is deleted', async () => {
    composio.connectedAccounts.list
      .mockResolvedValueOnce({ items: [connectedAccount()], nextCursor: 'next-page' })
      .mockResolvedValueOnce({
        items: [connectedAccount({ id: 'ca_drive', toolkit: { slug: 'googledrive' } })],
        nextCursor: null
      });
    composio.connectedAccounts.delete.mockResolvedValue({ success: true });
    const service = new ComposioConnectorService();

    await service.disconnectAll('user_123');

    expect(composio.connectedAccounts.delete).toHaveBeenCalledTimes(2);
    expect(composio.connectedAccounts.delete).toHaveBeenCalledWith('ca_gmail');
    expect(composio.connectedAccounts.delete).toHaveBeenCalledWith('ca_drive');
  });

  it('does not mutate an account that is not owned by the signed-in user', async () => {
    composio.connectedAccounts.list.mockResolvedValue({
      items: [connectedAccount({ id: 'ca_other' })],
      nextCursor: null
    });

    const service = new ComposioConnectorService();

    await expect(
      service.disconnect('user_123', 'ca_not_owned')
    ).rejects.toThrow('Connected account not found for this user.');
    expect(composio.connectedAccounts.delete).not.toHaveBeenCalled();
  });

  it('stages a local file for a connector tool', async () => {
    vi.stubEnv('DONY_COMPOSIO_TOOLKITS', 'googledrive');
    vi.resetModules();
    ({ ComposioConnectorService } =
      await import('../src/composioConnectorService'));
    const stagedFile = {
      name: 'report.pptx',
      mimetype:
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      s3key: 'staged/report.pptx'
    };
    composio.files.upload.mockResolvedValue(stagedFile);
    const service = new ComposioConnectorService();
    const file = new File(['deck'], 'report.pptx', {
      type: stagedFile.mimetype
    });

    await expect(
      service.stageFile({
        file,
        toolkit: 'googledrive',
        toolSlug: 'GOOGLEDRIVE_UPLOAD_FILE'
      })
    ).resolves.toEqual(stagedFile);
    expect(composio.files.upload).toHaveBeenCalledWith({
      file,
      toolkitSlug: 'googledrive',
      toolSlug: 'GOOGLEDRIVE_UPLOAD_FILE'
    });
  });
});
