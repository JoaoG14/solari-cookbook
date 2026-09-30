import { betterAuth } from 'better-auth';
import { bearer } from 'better-auth/plugins';

import { assertNever, config } from './config';
import { deleteDonyAccountData } from './cloudStore';
import { composioConnectorService } from './composioConnectorService';
import { createDatabase } from './database';

const database = createDatabase(config.d1);

const socialProviders = (() => {
  switch (config.auth.type) {
    case 'google':
      return {
        google: {
          clientId: config.auth.clientId,
          clientSecret: config.auth.clientSecret
        },
        apple: {
          clientId: config.auth.appleAppBundleIdentifier,
          appBundleIdentifier: config.auth.appleAppBundleIdentifier,
          mapProfileToUser: (profile: { email?: string; sub: string }) => ({
            email:
              profile.email ?? `${profile.sub}@apple.placeholder.invalid`
          })
        }
      };
    case 'dev':
      return {};
    default:
      return assertNever(config.auth);
  }
})();

export const auth = betterAuth({
  appName: 'Dony',
  baseURL: config.baseUrl,
  database: database.binding as unknown as NonNullable<Parameters<typeof betterAuth>[0]>['database'],
  trustedOrigins: config.trustedOrigins,
  socialProviders,
  user: {
    deleteUser: {
      enabled: true,
      beforeDelete: async (user) => {
        await composioConnectorService.disconnectAll(user.id);
        await deleteDonyAccountData(database, user.id);
      }
    }
  },
  plugins: [bearer()]
});
