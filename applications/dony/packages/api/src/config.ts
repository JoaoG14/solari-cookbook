type DonyApiConfig = {
  port: number;
  baseUrl: string;
  d1: { url: string; token: string };
  trustedOrigins: string[];
  modelGateway:
    | { type: 'dev' }
    | { type: 'openai'; apiKey: string; model: string; baseUrl: string };
  composio:
    | { enabled: false; toolkits: string[]; disabledReason: string }
    | {
        enabled: true;
        apiKey: string;
        toolkits: string[];
        gmailToolkitVersion: string;
        googleDriveToolkitVersion: string;
      };
  auth:
    | { type: 'dev'; token: string }
    | {
        type: 'google';
        clientId: string;
        clientSecret: string;
        appleAppBundleIdentifier: string;
      };
};

export const assertNever = (value: never): never => {
  throw new Error(`Unknown value: ${JSON.stringify(value)}`);
};

const defaultBaseUrl = 'http://127.0.0.1:8787';

const readOptional = (key: string): string | null => {
  const value = process.env[key]?.trim();

  return value ? value : null;
};

const readRequired = (key: string): string => {
  const value = readOptional(key);

  if (!value) {
    throw new Error(`${key} is required.`);
  }

  return value;
};

const readAuthConfig = (): DonyApiConfig['auth'] => {
  const token = readOptional('DONY_API_DEV_AUTH_TOKEN');

  if (token) {
    return { type: 'dev', token };
  }

  return {
    type: 'google',
    clientId: readRequired('GOOGLE_CLIENT_ID'),
    clientSecret: readRequired('GOOGLE_CLIENT_SECRET'),
    appleAppBundleIdentifier:
      readOptional('DONY_APPLE_APP_BUNDLE_IDENTIFIER') ?? 'com.dony.solari.mobile'
  };
};

const readModelGatewayConfig = (): DonyApiConfig['modelGateway'] => {
  const gateway = readOptional('DONY_MODEL_GATEWAY') ?? 'dev';

  switch (gateway) {
    case 'dev':
      return { type: 'dev' };
    case 'openai':
      return {
        type: 'openai',
        apiKey: readRequired('DONY_OPENAI_API_KEY'),
        model: readRequired('DONY_OPENAI_MODEL'),
        baseUrl:
          readOptional('DONY_OPENAI_BASE_URL') ?? 'https://api.openai.com'
      };
    default:
      throw new Error(`Unsupported DONY_MODEL_GATEWAY: ${gateway}`);
  }
};

const parsePort = (value: string | undefined): number => {
  const port = Number(value ?? '8787');

  if (!Number.isInteger(port) || port <= 0) {
    throw new Error('PORT must be a positive integer.');
  }

  return port;
};

const readBaseUrl = (): string => {
  const explicitBaseUrl = readOptional('DONY_API_BASE_URL');

  if (explicitBaseUrl) {
    return explicitBaseUrl;
  }

  const railwayDomain = readOptional('RAILWAY_PUBLIC_DOMAIN');

  if (railwayDomain) {
    return `https://${railwayDomain}`;
  }

  return defaultBaseUrl;
};

const parseOrigins = (value: string | null): string[] => {
  const origins = value
    ? value
        .split(',')
        .map((origin) => origin.trim())
        .filter(Boolean)
    : [];

  return [...new Set([defaultBaseUrl, 'http://127.0.0.1:5173', ...origins])];
};

const readComposioConfig = (): DonyApiConfig['composio'] => {
  const toolkits = (
    readOptional('DONY_COMPOSIO_TOOLKITS') ??
    'gmail,googlecalendar,googledrive,googledocs,googlesheets,googleslides,outlook,excel,microsoft_teams,slack,asana,airtable,confluence,zoom,canva,cloudflare,figma,granola_mcp,hugging_face,linear,notion,render,stripe,supabase,vercel'
  )
    .split(',')
    .map((toolkit) => toolkit.trim().toLowerCase())
    .filter(Boolean);
  const apiKey =
    readOptional('DONY_COMPOSIO_API_KEY') ?? readOptional('COMPOSIO_API_KEY');
  const explicitEnabled = readOptional('DONY_COMPOSIO_ENABLED');
  const isDisabled = ['0', 'false', 'no', 'off'].includes(
    explicitEnabled?.toLowerCase() ?? ''
  );

  if (isDisabled) {
    return {
      enabled: false,
      toolkits,
      disabledReason: 'Composio connectors are disabled by env.'
    };
  }

  if (!apiKey) {
    return {
      enabled: false,
      toolkits,
      disabledReason: 'Set DONY_COMPOSIO_API_KEY or COMPOSIO_API_KEY.'
    };
  }

  return {
    enabled: true,
    apiKey,
    toolkits,
    gmailToolkitVersion:
      readOptional('DONY_COMPOSIO_GMAIL_VERSION') ?? '20260721_00',
    googleDriveToolkitVersion:
      readOptional('DONY_COMPOSIO_GOOGLE_DRIVE_VERSION') ?? '20260826_00'
  };
};

export const config: DonyApiConfig = {
  port: parsePort(process.env.PORT ?? process.env.DONY_API_PORT),
  baseUrl: readBaseUrl(),
  d1: {
    url: readOptional('DONY_D1_URL') ?? '',
    token: readOptional('DONY_D1_TOKEN') ?? ''
  },
  trustedOrigins: parseOrigins(readOptional('DONY_API_TRUSTED_ORIGINS')),
  modelGateway: readModelGatewayConfig(),
  composio: readComposioConfig(),
  auth: readAuthConfig()
};
