import { z } from 'zod';

export const authUserSchema = z.object({
  id: z.string(),
  email: z.string().nullable(),
  name: z.string().nullable(),
  avatarUrl: z.string().nullable()
});

export type AuthUser = z.infer<typeof authUserSchema>;

export const authAccountMetadataSchema = authUserSchema.extend({
  lastSignedInAt: z.string()
});

export type AuthAccountMetadata = z.infer<typeof authAccountMetadataSchema>;

export const authSessionSnapshotSchema = z.discriminatedUnion('status', [
  z.object({
    status: z.literal('signed_out'),
    user: z.null()
  }),
  z.object({
    status: z.literal('signed_in'),
    user: authUserSchema
  })
]);

export type AuthSessionSnapshot = z.infer<typeof authSessionSnapshotSchema>;

export const authStartResultSchema = z.object({
  url: z.string().url()
});

export type AuthStartResult = z.infer<typeof authStartResultSchema>;

export const authDesktopStartInputSchema = z.object({
  callbackUrl: z.string().min(1)
});

export type AuthDesktopStartInput = z.infer<
  typeof authDesktopStartInputSchema
>;

export const authDesktopExchangeInputSchema = z.object({
  code: z.string().min(1)
});

export type AuthDesktopExchangeInput = z.infer<
  typeof authDesktopExchangeInputSchema
>;

export const authDesktopExchangeResponseSchema = z.object({
  token: z.string().min(1),
  user: authUserSchema
});

export type AuthDesktopExchangeResponse = z.infer<
  typeof authDesktopExchangeResponseSchema
>;

export const authMeResponseSchema = z.object({
  user: authUserSchema
});

export type AuthMeResponse = z.infer<typeof authMeResponseSchema>;
