import { z } from 'zod';

import { nonEmptyTrimmedStringSchema } from './shared';

export const connectorToolkitStatusSchema = z.object({
  slug: nonEmptyTrimmedStringSchema,
  name: nonEmptyTrimmedStringSchema,
  logoUrl: z.string().url().nullable().optional(),
  isConnected: z.boolean(),
  status: z.string(),
  connectedAccountId: z.string().nullable(),
  authConfigId: z.string().nullable()
});

export type ConnectorToolkitStatus = z.infer<
  typeof connectorToolkitStatusSchema
>;

export const connectorsStatusSchema = z.object({
  enabled: z.boolean(),
  disabledReason: z.string().nullable(),
  toolkits: connectorToolkitStatusSchema.array()
});

export type ConnectorsStatus = z.infer<typeof connectorsStatusSchema>;

export const connectorConnectResultSchema = z.object({
  url: nonEmptyTrimmedStringSchema
});

export type ConnectorConnectResult = z.infer<
  typeof connectorConnectResultSchema
>;

export const connectorRefreshResultSchema = z.object({
  url: z.string().url().nullable()
});

export type ConnectorRefreshResult = z.infer<
  typeof connectorRefreshResultSchema
>;

export const connectorLocalFileSchema = z.object({
  argumentName: nonEmptyTrimmedStringSchema
    .regex(/^[A-Za-z_][A-Za-z0-9_]*$/)
    .refine((value) => value !== '__proto__'),
  path: nonEmptyTrimmedStringSchema,
  mimeType: nonEmptyTrimmedStringSchema.regex(/^\S+\/\S+$/)
});

export type ConnectorLocalFile = z.infer<typeof connectorLocalFileSchema>;

export const connectorLocalFilesSchema = connectorLocalFileSchema
  .array()
  .max(10);

export const connectorStagedFileSchema = z.object({
  name: nonEmptyTrimmedStringSchema,
  mimetype: nonEmptyTrimmedStringSchema,
  s3key: nonEmptyTrimmedStringSchema
});

export type ConnectorStagedFile = z.infer<typeof connectorStagedFileSchema>;

export const connectorFileMaxBytes = 25 * 1024 * 1024;
