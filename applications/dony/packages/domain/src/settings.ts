import { z } from 'zod';

import { agentResponseLanguageSchema } from './agentResponseLanguages';
import { providerTypeSchema } from './providers';
import { shortcutAcceleratorSchema } from './shortcuts';
import { taskOutputDesignSchema } from './taskOutputDesigns';

export const browserBackendSchema = z.enum(['cua', 'dony']);
export type BrowserBackend = z.infer<typeof browserBackendSchema>;

export const appThemeSchema = z.enum(['dark', 'light', 'system']);

export type AppTheme = z.infer<typeof appThemeSchema>;

export const agentsModeSchema = z.enum(['off', 'suggest', 'proactive']);

export type AgentsMode = z.infer<typeof agentsModeSchema>;

export const notchNotificationModeSchema = z.enum([
  'off',
  'compact',
  'expanded'
]);

export type NotchNotificationMode = z.infer<typeof notchNotificationModeSchema>;

export const presentationReferenceFileKindSchema = z.enum([
  'presentation',
  'document',
  'spreadsheet'
]);

export type PresentationReferenceFileKind = z.infer<
  typeof presentationReferenceFileKindSchema
>;

export const presentationReferenceFileSchema = z.object({
  id: z.string().uuid(),
  name: z.string().trim().min(1),
  path: z.string().trim().min(1),
  size: z.number().int().nonnegative(),
  kind: presentationReferenceFileKindSchema
});

export type PresentationReferenceFile = z.infer<
  typeof presentationReferenceFileSchema
>;

export const appSettingsPreferencesSchema = z.object({
  browserBackend: browserBackendSchema.optional(),
  theme: appThemeSchema,
  reduceMotion: z.boolean(),
  launchAtLogin: z.boolean(),
  quickAddShortcutEnabled: z.boolean(),
  quickAddShortcutAccelerator: shortcutAcceleratorSchema,
  defaultAiProvider: providerTypeSchema,
  agentsMode: agentsModeSchema,
  agentResponseLanguage: agentResponseLanguageSchema,
  taskOutputAutoOpenEnabled: z.boolean(),
  taskOutputDesign: taskOutputDesignSchema,
  presentationReferenceFiles: presentationReferenceFileSchema.array(),
  notchNotificationMode: notchNotificationModeSchema,
  notchNotificationSoundEnabled: z.boolean(),
  devDemoRepliesEnabled: z.boolean()
});

export type AppSettingsPreferences = z.infer<
  typeof appSettingsPreferencesSchema
>;

export const updateAppSettingsInputSchema = z.discriminatedUnion('key', [
  z.object({ key: z.literal('browserBackend'), value: browserBackendSchema }),
  z.object({ key: z.literal('theme'), value: appThemeSchema }),
  z.object({ key: z.literal('reduceMotion'), value: z.boolean() }),
  z.object({ key: z.literal('launchAtLogin'), value: z.boolean() }),
  z.object({ key: z.literal('quickAddShortcutEnabled'), value: z.boolean() }),
  z.object({
    key: z.literal('quickAddShortcutAccelerator'),
    value: shortcutAcceleratorSchema
  }),
  z.object({ key: z.literal('defaultAiProvider'), value: providerTypeSchema }),
  z.object({ key: z.literal('agentsMode'), value: agentsModeSchema }),
  z.object({
    key: z.literal('agentResponseLanguage'),
    value: agentResponseLanguageSchema
  }),
  z.object({
    key: z.literal('taskOutputAutoOpenEnabled'),
    value: z.boolean()
  }),
  z.object({
    key: z.literal('taskOutputDesign'),
    value: taskOutputDesignSchema
  }),
  z.object({
    key: z.literal('presentationReferenceFiles'),
    value: presentationReferenceFileSchema.array()
  }),
  z.object({
    key: z.literal('notchNotificationMode'),
    value: notchNotificationModeSchema
  }),
  z.object({
    key: z.literal('notchNotificationSoundEnabled'),
    value: z.boolean()
  }),
  z.object({ key: z.literal('devDemoRepliesEnabled'), value: z.boolean() })
]);

export type UpdateAppSettingsInput = z.infer<
  typeof updateAppSettingsInputSchema
>;

export const appSettingsSnapshotSchema = appSettingsPreferencesSchema.extend({
  appVersion: z.string(),
  userDataPath: z.string(),
  platform: z.string(),
  quickAddShortcut: z.string().nullable(),
  isQuickAddShortcutSupported: z.boolean(),
  isQuickAddShortcutRegistered: z.boolean(),
  quickAddShortcutConflictHint: z.string().nullable(),
  isDevRunDiagnosticsEnabled: z.boolean(),
  isDevReplyDemoEnabled: z.boolean()
});

export type AppSettingsSnapshot = z.infer<typeof appSettingsSnapshotSchema>;

export const setupStatusSchema = z.enum(['ready', 'error', 'unknown']);

export type SetupStatus = z.infer<typeof setupStatusSchema>;

export const cuaDevStatusSchema = z.object({
  command: z.string(),
  status: setupStatusSchema,
  driverInstalled: z.boolean(),
  daemonRunning: z.boolean(),
  accessibility: setupStatusSchema,
  screenRecording: setupStatusSchema,
  lastCheckedAt: z.string().datetime(),
  lastError: z.string().nullable(),
  installHint: z.string()
});

export type CuaDevStatus = z.infer<typeof cuaDevStatusSchema>;
