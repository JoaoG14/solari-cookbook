import { z } from 'zod';

export const browserKindSchema = z.enum([
  'chrome',
  'arc',
  'brave',
  'edge',
  'dia',
  'comet',
  'safari'
]);

export type BrowserKind = z.infer<typeof browserKindSchema>;

export const detectedBrowserProfileSchema = z.object({
  browser: browserKindSchema,
  profilePath: z.string().min(1),
  name: z.string().min(1),
  email: z.string().nullable(),
  isImported: z.boolean()
});

export type DetectedBrowserProfile = z.infer<
  typeof detectedBrowserProfileSchema
>;

export const browserProfileSchema = z.object({
  id: z.string().uuid(),
  browser: browserKindSchema,
  profilePath: z.string().min(1),
  name: z.string().min(1),
  email: z.string().nullable(),
  importedAt: z.string().datetime(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime()
});

export type BrowserProfile = z.infer<typeof browserProfileSchema>;

export const importBrowserProfileInputSchema = z.object({
  browser: browserKindSchema,
  profilePath: z.string().min(1),
  name: z.string().min(1),
  email: z.string().nullable().optional()
});

export type ImportBrowserProfileInput = z.infer<
  typeof importBrowserProfileInputSchema
>;

export const browserBoundsSchema = z.object({
  x: z.number().int().nonnegative(),
  y: z.number().int().nonnegative(),
  width: z.number().int().positive(),
  height: z.number().int().positive()
});

export type BrowserBounds = z.infer<typeof browserBoundsSchema>;

export const browserTabSchema = z.object({
  id: z.string().uuid(),
  url: z.string(),
  title: z.string(),
  isLoading: z.boolean()
});

export type BrowserTab = z.infer<typeof browserTabSchema>;

export const browserViewStateSchema = z.object({
  threadId: z.string().uuid(),
  profileId: z.string().uuid(),
  activeTabId: z.string().uuid(),
  tabs: z.array(browserTabSchema).min(1),
  url: z.string(),
  title: z.string(),
  canGoBack: z.boolean(),
  canGoForward: z.boolean(),
  isLoading: z.boolean(),
  isVisible: z.boolean()
});

export type BrowserViewState = z.infer<typeof browserViewStateSchema>;

export const browserCommandInputSchema = z.object({
  threadId: z.string().uuid(),
  command: z.array(z.string()).min(1)
});

export type BrowserCommandInput = z.infer<typeof browserCommandInputSchema>;

export const externalBrowserWindowSchema = z.object({
  pid: z.number().int().positive(),
  windowId: z.string().regex(/^\d+$/),
  title: z.string(),
  appName: z.string()
});
export type ExternalBrowserWindow = z.infer<typeof externalBrowserWindowSchema>;
export type ExternalBrowserConnection = ExternalBrowserWindow & {
  threadId: string;
};

export type ExternalBrowserState = {
  threadId: string;
  status: 'idle' | 'opening' | 'connected' | 'paused' | 'error';
  connection: ExternalBrowserConnection | null;
  error: string | null;
};
