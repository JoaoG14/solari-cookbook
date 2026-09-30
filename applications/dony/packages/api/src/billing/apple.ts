import {
  AppStoreServerAPIClient,
  Environment,
  SignedDataVerifier,
  Type,
  type JWSTransactionDecodedPayload
} from '@apple/app-store-server-library';
import { CloudError } from '../cloudCommands';
import { appleRootG3 } from './appleRoot';
import { billingProducts } from './catalog';
import type { VerifiedPurchase } from './store';

export class AppleBilling {
  readonly configured: boolean;
  readonly environment: Environment;
  private readonly verifier: SignedDataVerifier | null;
  private readonly client: AppStoreServerAPIClient | null;
  private readonly sandboxVerifier: SignedDataVerifier | null;
  private readonly sandboxClient: AppStoreServerAPIClient | null;
  constructor(env: NodeJS.ProcessEnv = process.env) {
    this.environment =
      env.DONY_APP_STORE_ENVIRONMENT === 'Sandbox'
        ? Environment.SANDBOX
        : Environment.PRODUCTION;
    const appId = Number(env.DONY_APP_STORE_APP_ID);
    const key = env.DONY_APP_STORE_PRIVATE_KEY?.replace(/\\n/g, '\n');
    const keyId = env.DONY_APP_STORE_KEY_ID;
    const issuer = env.DONY_APP_STORE_ISSUER_ID;
    this.configured = Boolean(
      key &&
      keyId &&
      issuer &&
      (this.environment === Environment.SANDBOX ||
        (Number.isSafeInteger(appId) && appId > 0))
    );
    this.verifier = this.configured
      ? new SignedDataVerifier(
          [appleRootG3],
          true,
          this.environment,
          'com.dony.solari.mobile',
          appId || undefined
        )
      : null;
    this.client = this.configured
      ? new AppStoreServerAPIClient(
          key!,
          keyId!,
          issuer!,
          'com.dony.solari.mobile',
          this.environment
        )
      : null;
    this.sandboxVerifier =
      this.configured && this.environment === Environment.PRODUCTION
        ? new SignedDataVerifier(
            [appleRootG3],
            true,
            Environment.SANDBOX,
            'com.dony.solari.mobile'
          )
        : null;
    this.sandboxClient = this.sandboxVerifier
      ? new AppStoreServerAPIClient(
          key!,
          keyId!,
          issuer!,
          'com.dony.solari.mobile',
          Environment.SANDBOX
        )
      : null;
  }

  private normalize(value: JWSTransactionDecodedPayload): VerifiedPurchase {
    const product = value.productId
      ? billingProducts[value.productId]
      : undefined;
    if (
      !product ||
      !value.transactionId ||
      !value.originalTransactionId ||
      !value.appAccountToken ||
      !value.purchaseDate ||
      !value.signedDate ||
      value.bundleId !== 'com.dony.solari.mobile' ||
      (value.environment !== this.environment &&
        !(this.sandboxVerifier && value.environment === Environment.SANDBOX)) ||
      value.inAppOwnershipType === 'FAMILY_SHARED' ||
      (product.kind === 'subscription'
        ? value.type !== Type.AUTO_RENEWABLE_SUBSCRIPTION || !value.expiresDate
        : value.type !== Type.CONSUMABLE) ||
      (value.quantity !== undefined && value.quantity !== 1)
    )
      throw new CloudError(
        400,
        'This purchase could not be verified for Dony.'
      );
    return {
      id: `${value.environment}:${value.transactionId}`,
      accountToken: value.appAccountToken.toLowerCase(),
      originalId: `${value.environment}:${value.originalTransactionId}`,
      productId: value.productId!,
      purchasedAt: value.purchaseDate,
      expiresAt: value.expiresDate ?? null,
      signedAt: value.signedDate,
      revokedAt: value.revocationDate ?? null,
      upgraded: value.isUpgraded ?? false
    };
  }

  async transaction(signedTransaction: string): Promise<VerifiedPurchase> {
    if (!this.verifier || !this.client)
      throw new CloudError(
        503,
        'Purchases are not available yet. Please try again later.'
      );
    let incoming: JWSTransactionDecodedPayload;
    try {
      incoming =
        await this.verifier.verifyAndDecodeTransaction(signedTransaction);
    } catch {
      try {
        if (!this.sandboxVerifier) throw new Error('No sandbox verifier.');
        incoming =
          await this.sandboxVerifier.verifyAndDecodeTransaction(
            signedTransaction
          );
      } catch {
        throw new CloudError(400, 'This purchase could not be verified.');
      }
    }
    this.normalize(incoming);
    // Read current Apple state so restores and old notifications cannot resurrect a refund.
    return this.transactionId(
      incoming.transactionId!,
      incoming.environment === Environment.SANDBOX
    );
  }

  async transactionId(id: string, sandbox = false): Promise<VerifiedPurchase> {
    const verifier = sandbox
      ? (this.sandboxVerifier ??
        (this.environment === Environment.SANDBOX ? this.verifier : null))
      : this.verifier;
    const client = sandbox
      ? (this.sandboxClient ??
        (this.environment === Environment.SANDBOX ? this.client : null))
      : this.client;
    if (!verifier || !client)
      throw new CloudError(503, 'Purchases are not configured.');
    const result = await client.getTransactionInfo(id);
    if (!result.signedTransactionInfo)
      throw new CloudError(503, 'Apple has not confirmed this purchase yet.');
    return this.normalize(
      await verifier.verifyAndDecodeTransaction(result.signedTransactionInfo)
    );
  }

  async notification(signedPayload: string): Promise<VerifiedPurchase | null> {
    if (!this.verifier)
      throw new CloudError(503, 'Purchases are not configured.');
    let event;
    let verifier = this.verifier;
    try {
      event = await verifier.verifyAndDecodeNotification(signedPayload);
    } catch {
      try {
        if (!this.sandboxVerifier) throw new Error('No sandbox verifier.');
        verifier = this.sandboxVerifier;
        event = await verifier.verifyAndDecodeNotification(signedPayload);
      } catch {
        throw new CloudError(400, 'Invalid App Store notification.');
      }
    }
    const transaction = event.data?.signedTransactionInfo;
    if (!transaction) return null;
    const decoded = await verifier.verifyAndDecodeTransaction(transaction);
    this.normalize(decoded);
    return this.transactionId(
      decoded.transactionId!,
      decoded.environment === Environment.SANDBOX
    );
  }
}
