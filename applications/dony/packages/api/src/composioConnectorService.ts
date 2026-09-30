import { Composio } from '@composio/core';

import {
  connectorStagedFileSchema,
  type ConnectorStagedFile,
  type ConnectorToolkitStatus,
  type ConnectorsStatus
} from '@dony/domain';

import { config } from './config';

type OwnedConnectedAccount = Awaited<
  ReturnType<Composio['connectedAccounts']['list']>
>['items'][number];

type ConnectorUseInput =
  | {
      action: 'list_toolkits';
      toolkit?: string | null;
      query?: string | null;
      toolSlug?: string | null;
      argumentsJson?: string | null;
    }
  | {
      action: 'search_tools';
      toolkit?: string | null;
      query: string;
      toolSlug?: string | null;
      argumentsJson?: string | null;
    }
  | {
      action: 'execute_tool';
      toolkit?: string | null;
      query?: string | null;
      toolSlug: string;
      arguments: Record<string, unknown>;
    }
  | {
      action: 'authorize_toolkit';
      toolkit: string;
      query?: string | null;
      toolSlug?: string | null;
      argumentsJson?: string | null;
    };

const isRecord = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === 'object' && !Array.isArray(value);

const parseArgumentsJson = (value: unknown): Record<string, unknown> => {
  if (value === null || value === undefined || value === '') {
    return {};
  }

  if (typeof value !== 'string') {
    throw new Error('argumentsJson must be a JSON object string.');
  }

  const parsed = JSON.parse(value) as unknown;

  if (!isRecord(parsed)) {
    throw new Error('argumentsJson must parse to a JSON object.');
  }

  return parsed;
};

const connectorUseInput = (value: unknown): ConnectorUseInput => {
  const input = isRecord(value) ? value : {};
  const action = input.action;

  if (action === 'list_toolkits') {
    return { action };
  }

  if (action === 'search_tools') {
    if (typeof input.query !== 'string' || input.query.trim().length === 0) {
      throw new Error('query is required.');
    }

    return {
      action,
      toolkit: typeof input.toolkit === 'string' ? input.toolkit : null,
      query: input.query.trim()
    };
  }

  if (action === 'execute_tool') {
    if (
      typeof input.toolSlug !== 'string' ||
      input.toolSlug.trim().length === 0
    ) {
      throw new Error('toolSlug is required.');
    }

    return {
      action,
      toolSlug: input.toolSlug.trim(),
      arguments: parseArgumentsJson(input.argumentsJson)
    };
  }

  if (action === 'authorize_toolkit') {
    if (
      typeof input.toolkit !== 'string' ||
      input.toolkit.trim().length === 0
    ) {
      throw new Error('toolkit is required.');
    }

    return {
      action,
      toolkit: input.toolkit.trim().toLowerCase()
    };
  }

  throw new Error('Unknown connector action.');
};

const connectorUnavailableStatus = (
  toolkits: string[]
): ConnectorToolkitStatus[] =>
  toolkits.map((toolkit) => ({
    slug: toolkit,
    name: toolkit,
    logoUrl: `https://logos.composio.dev/api/${encodeURIComponent(toolkit)}`,
    isConnected: false,
    status: 'disabled',
    connectedAccountId: null,
    authConfigId: null
  }));

export class ComposioConnectorService {
  private readonly composio = config.composio.enabled
    ? new Composio({
        apiKey: config.composio.apiKey,
        allowTracking: false,
        toolkitVersions: {
          gmail: config.composio.gmailToolkitVersion,
          googledrive: config.composio.googleDriveToolkitVersion
        }
      })
    : null;

  public isEnabled(): boolean {
    return this.composio !== null;
  }

  public async list(userId: string): Promise<ConnectorsStatus> {
    if (!this.composio) {
      return {
        enabled: false,
        disabledReason: config.composio.enabled
          ? 'Composio connectors are unavailable.'
          : config.composio.disabledReason,
        toolkits: connectorUnavailableStatus(config.composio.toolkits)
      };
    }

    const session = await this.composio.create(userId, {
      toolkits: config.composio.toolkits,
      manageConnections: true
    });
    const response = await session.toolkits({
      toolkits: config.composio.toolkits
    });
    const ownedAccounts = await this.listOwnedAccounts(
      this.composio,
      userId,
      config.composio.toolkits
    );
    const ownedAccountByToolkit = new Map<string, OwnedConnectedAccount>();

    for (const account of ownedAccounts) {
      const slug = account.toolkit.slug.toLowerCase();
      const current = ownedAccountByToolkit.get(slug);

      if (!current || account.updatedAt > current.updatedAt) {
        ownedAccountByToolkit.set(slug, account);
      }
    }

    const responseBySlug = new Map(
      response.items.map((item) => [item.slug.toLowerCase(), item])
    );

    return {
      enabled: true,
      disabledReason: null,
      toolkits: config.composio.toolkits.map((slug) => {
        const item = responseBySlug.get(slug);
        const sessionAccount = item?.connection?.connectedAccount;
        const ownedAccount = ownedAccountByToolkit.get(slug);
        const accountId = sessionAccount?.id ?? ownedAccount?.id ?? null;
        const accountStatus =
          sessionAccount?.status ?? ownedAccount?.status ?? 'disconnected';

        return {
          slug,
          name: item?.name ?? slug,
          logoUrl:
            item?.logo ??
            `https://logos.composio.dev/api/${encodeURIComponent(slug)}`,
          isConnected:
            (item?.connection?.isActive ?? false) || accountStatus === 'ACTIVE',
          status: accountStatus,
          connectedAccountId: accountId,
          authConfigId:
            item?.connection?.authConfig?.id ??
            ownedAccount?.authConfig.id ??
            null
        };
      })
    };
  }

  public async connect(userId: string, toolkit: string): Promise<string> {
    if (!this.composio) {
      throw new Error('Composio connectors are disabled.');
    }

    const normalizedToolkit = toolkit.trim().toLowerCase();

    if (!config.composio.toolkits.includes(normalizedToolkit)) {
      throw new Error(`Connector toolkit is not enabled: ${normalizedToolkit}`);
    }

    const session = await this.composio.create(userId, {
      toolkits: config.composio.toolkits,
      manageConnections: true
    });
    const connection = await session.authorize(normalizedToolkit);

    if (!connection.redirectUrl) {
      throw new Error('Composio did not return a connect URL.');
    }

    return connection.redirectUrl;
  }

  public async refresh(
    userId: string,
    connectedAccountId: string
  ): Promise<string | null> {
    const composio = this.requiredComposio();
    const accountId = await this.requireOwnedAccount(
      composio,
      userId,
      connectedAccountId
    );
    const result = await composio.connectedAccounts.refresh(accountId);

    return result.redirect_url;
  }

  public async setEnabled(
    userId: string,
    connectedAccountId: string,
    enabled: boolean
  ): Promise<void> {
    const composio = this.requiredComposio();
    const accountId = await this.requireOwnedAccount(
      composio,
      userId,
      connectedAccountId
    );
    const result = enabled
      ? await composio.connectedAccounts.enable(accountId)
      : await composio.connectedAccounts.disable(accountId);

    if (!result.success) {
      throw new Error(
        `Composio could not ${enabled ? 'enable' : 'disable'} the connected account.`
      );
    }
  }

  public async disconnect(
    userId: string,
    connectedAccountId: string
  ): Promise<void> {
    const composio = this.requiredComposio();
    const accountId = await this.requireOwnedAccount(
      composio,
      userId,
      connectedAccountId
    );
    const result = await composio.connectedAccounts.delete(accountId);

    if (!result.success) {
      throw new Error('Composio could not disconnect the account.');
    }
  }

  public async disconnectAll(userId: string): Promise<void> {
    if (!this.composio) return;

    const accounts = await this.listOwnedAccounts(this.composio, userId);
    for (const account of accounts) {
      const result = await this.composio.connectedAccounts.delete(account.id);
      if (!result.success) {
        throw new Error('Composio could not disconnect the account.');
      }
    }
  }

  public async execute(
    userId: string,
    rawInput: unknown,
    signal?: AbortSignal
  ): Promise<unknown> {
    signal?.throwIfAborted();

    if (!this.composio) {
      throw new Error('Composio connectors are disabled.');
    }

    const input = connectorUseInput(rawInput);
    signal?.throwIfAborted();
    const session = await this.composio.create(userId, {
      toolkits: config.composio.toolkits,
      manageConnections: true
    });
    signal?.throwIfAborted();

    switch (input.action) {
      case 'list_toolkits':
        return await session.toolkits({ toolkits: config.composio.toolkits });
      case 'search_tools':
        return await session.search({
          query: input.query,
          toolkits: input.toolkit ? [input.toolkit] : config.composio.toolkits
        });
      case 'execute_tool':
        return await session.execute(input.toolSlug, input.arguments ?? {});
      case 'authorize_toolkit':
        return {
          redirectUrl: await this.connect(userId, input.toolkit)
        };
      default:
        return input satisfies never;
    }
  }

  public async stageFile(input: {
    file: File;
    toolkit: string;
    toolSlug: string;
    signal?: AbortSignal;
  }): Promise<ConnectorStagedFile> {
    input.signal?.throwIfAborted();
    const composio = this.requiredComposio();
    const toolkit = input.toolkit.trim().toLowerCase();
    const toolSlug = input.toolSlug.trim();

    if (!config.composio.toolkits.includes(toolkit)) {
      throw new Error(`Connector toolkit is not enabled: ${toolkit}`);
    }

    if (!toolSlug) {
      throw new Error('Connector tool slug is required.');
    }

    const stagedFile = await composio.files.upload({
      file: input.file,
      toolkitSlug: toolkit,
      toolSlug
    });
    input.signal?.throwIfAborted();

    return connectorStagedFileSchema.parse(stagedFile);
  }

  private requiredComposio(): Composio {
    if (!this.composio) {
      throw new Error('Composio connectors are disabled.');
    }

    return this.composio;
  }

  private async requireOwnedAccount(
    composio: Composio,
    userId: string,
    connectedAccountId: string
  ): Promise<string> {
    const accountId = connectedAccountId.trim();

    if (!accountId) {
      throw new Error('Connected account ID is required.');
    }

    const accounts = await this.listOwnedAccounts(composio, userId);

    if (accounts.some((account) => account.id === accountId)) {
      return accountId;
    }

    throw new Error('Connected account not found for this user.');
  }

  private async listOwnedAccounts(
    composio: Composio,
    userId: string,
    toolkitSlugs?: string[]
  ): Promise<OwnedConnectedAccount[]> {
    const items: OwnedConnectedAccount[] = [];
    let cursor: string | null | undefined;

    do {
      const response = await composio.connectedAccounts.list({
        userIds: [userId],
        toolkitSlugs,
        cursor,
        limit: 100
      });

      items.push(...response.items);
      cursor = response.nextCursor;
    } while (cursor);

    return items;
  }
}

export const composioConnectorService = new ComposioConnectorService();
