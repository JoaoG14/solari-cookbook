import type {
  ExternalBrowserState,
  ExternalBrowserConnection
} from './browser';
import { z } from 'zod';
import { chatThinkingSchema } from './chatThinking';

import {
  type Agent,
  type AgentWelcomeContextInput,
  type CreateAgentInput,
  type UpdateAgentPatch
} from './agents';
import {
  agentMessageSchema,
  agentThreadSchema,
  codexRunSchema,
  codexTimelineEventSchema,
  type AgentMessage,
  type AgentThread,
  type AgentThreadSummary,
  type CreateAgentThreadInput,
  type CodexRun,
  type CodexTimelineEvent
} from './chat';
import {
  type CreateProviderConfigInput,
  type ProviderConfig,
  type ProviderConfigDefaults,
  type ProviderConfigDraft,
  type ProviderConnectionCheck,
  type ProviderModelOption,
  type ProviderStatus,
  type ProviderType,
  type UpdateProviderConfigPatch,
  type CodexExecutionMode
} from './providers';
import type { AuthSessionSnapshot, AuthStartResult } from './auth';
import type {
  BrowserBounds,
  BrowserProfile,
  BrowserViewState,
  DetectedBrowserProfile,
  ImportBrowserProfileInput
} from './browser';
import {
  computerUseActivitySchema,
  type ComputerUseAllowedApp
} from './computerUse';
import type {
  ConnectorConnectResult,
  ConnectorRefreshResult,
  ConnectorsStatus
} from './connectors';
import type { ContextExtractorSnapshot } from './contextExtractor';
import type {
  RepliesSnapshot,
  ReplySuggestion,
  StartReplyTaskInput,
  StartReplyTaskResult,
  UpdateReplyDraftInput
} from './replies';
import {
  agentQuestionSchema,
  type AgentQuestionResponse,
  type PendingAgentQuestion
} from './questions';
import { nonEmptyTrimmedStringSchema } from './shared';
import {
  type AppSettingsSnapshot,
  type CuaDevStatus,
  type UpdateAppSettingsInput
} from './settings';
import type { HomeTaskAgentResult } from './taskResults';
import type { TaskSuggestionsSnapshot } from './taskSuggestions';
import type {
  CreateTaskInput,
  ReorderTasksInput,
  Task,
  TaskScreenshotImportInput,
  TaskTextImportInput,
  TaskTree,
  UpdateTaskPatch
} from './tasks';
import type {
  AttachMemorySpaceInput,
  CreateMemorySpaceInput,
  MemoryDocument,
  MemorySearchResult,
  MemorySnapshot,
  RememberMemoryInput,
  SaveMemoryDocumentInput
} from './memory';

export const agentChatSendResultSchema = z.object({
  thread: agentThreadSchema,
  messages: agentMessageSchema.array(),
  run: codexRunSchema
});

export type AgentChatSendResult = z.infer<typeof agentChatSendResultSchema>;

export const agentChatRunContextSchema = z.object({
  agentId: z.string().uuid(),
  agentName: nonEmptyTrimmedStringSchema,
  threadId: z.string().uuid(),
  threadTitle: nonEmptyTrimmedStringSchema,
  threadOrigin: z.enum(['direct', 'task']).default('direct'),
  taskId: z.string().uuid().nullable().default(null)
});

export type AgentChatRunContext = z.infer<typeof agentChatRunContextSchema>;

export const agentChatRunEventSchema = z.object({
  context: agentChatRunContextSchema,
  run: codexRunSchema,
  timelineEvent: codexTimelineEventSchema.nullable(),
  messages: agentMessageSchema.array().nullable(),
  activeQuestion: agentQuestionSchema.nullable().optional(),
  computerUse: computerUseActivitySchema.nullable().optional()
});

export type AgentChatRunEvent = z.infer<typeof agentChatRunEventSchema>;

export const agentChatTargetSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('latest'),
    agentId: z.string().uuid()
  }),
  z.object({
    type: z.literal('direct'),
    agentId: z.string().uuid()
  }),
  z.object({
    type: z.literal('thread'),
    agentId: z.string().uuid(),
    threadId: z.string().uuid()
  })
]);

export type AgentChatTarget = z.infer<typeof agentChatTargetSchema>;

export const agentChatAttachmentInputSchema = z.object({
  path: nonEmptyTrimmedStringSchema
});

export type AgentChatAttachmentInput = z.infer<
  typeof agentChatAttachmentInputSchema
>;

export const agentChatSendInputSchema = z.object({
  target: agentChatTargetSchema,
  thinking: chatThinkingSchema.optional(),
  message: z.string(),
  attachments: agentChatAttachmentInputSchema.array()
});

export type AgentChatSendInput = z.infer<typeof agentChatSendInputSchema>;

export const localFileAttachmentSchema = z.object({
  path: nonEmptyTrimmedStringSchema,
  name: nonEmptyTrimmedStringSchema,
  size: z.number().int().nonnegative()
});

export type LocalFileAttachment = z.infer<typeof localFileAttachmentSchema>;

export type OpenTerminalInput = {
  cwd: string;
  command?: string;
  args?: string[];
};

export type PickLocalDirectoryInput = {
  currentPath?: string | null;
};

export const tasksIpcChannels = {
  list: 'tasks:list',
  create: 'tasks:create',
  importScreenshot: 'tasks:import-screenshot',
  importText: 'tasks:import-text',
  reorder: 'tasks:reorder',
  update: 'tasks:update',
  toggle: 'tasks:toggle',
  delete: 'tasks:delete',
  acceptProactiveSuggestion: 'tasks:accept-proactive-suggestion',
  dismissProactiveSuggestion: 'tasks:dismiss-proactive-suggestion',
  retryProactivePlanning: 'tasks:retry-proactive-planning',
  answerProactiveQuestion: 'tasks:answer-proactive-question',
  listAgentResults: 'tasks:list-agent-results',
  acceptAgentResult: 'tasks:accept-agent-result',
  requestAgentResultChanges: 'tasks:request-agent-result-changes',
  dismissAgentResult: 'tasks:dismiss-agent-result',
  clearAgentResults: 'tasks:clear-agent-results',
  openTaskOutput: 'tasks:open-task-output',
  openTaskResultLink: 'tasks:open-task-result-link',
  deleteTaskOutput: 'tasks:delete-task-output',
  setTodoRouteActive: 'tasks:set-todo-route-active',
  changed: 'tasks:changed'
} as const;

export const taskSuggestionsIpcChannels = {
  getSnapshot: 'task-suggestions:get-snapshot',
  syncNow: 'task-suggestions:sync-now',
  accept: 'task-suggestions:accept',
  addToList: 'task-suggestions:add-to-list',
  dismiss: 'task-suggestions:dismiss',
  changed: 'task-suggestions:changed'
} as const;

export const contextExtractorIpcChannels = {
  getSnapshot: 'context-extractor:get-snapshot',
  syncNow: 'context-extractor:sync-now',
  changed: 'context-extractor:changed'
} as const;

export const agentsIpcChannels = {
  list: 'agents:list',
  get: 'agents:get',
  create: 'agents:create',
  generateWelcome: 'agents:generate-welcome',
  update: 'agents:update',
  delete: 'agents:delete'
} as const;

export const providersIpcChannels = {
  list: 'providers:list',
  get: 'providers:get',
  create: 'providers:create',
  update: 'providers:update',
  testDraft: 'providers:test-draft',
  getDefaults: 'providers:get-defaults',
  configure: 'providers:configure',
  models: 'providers:models',
  signIn: 'providers:sign-in'
} as const;

export const agentThreadsIpcChannels = {
  get: 'agent-threads:get',
  getDefault: 'agent-threads:get-default',
  getLatest: 'agent-threads:get-latest',
  getCurrent: 'agent-threads:get-current',
  create: 'agent-threads:create',
  listTaskThreads: 'agent-threads:list-task-threads',
  listRecent: 'agent-threads:list-recent',
  search: 'agent-threads:search',
  archive: 'agent-threads:archive',
  markViewed: 'agent-threads:mark-viewed',
  deleteHistoryThread: 'agent-threads:delete-history-thread',
  clearAgentHistory: 'agent-threads:clear-agent-history',
  clearHistory: 'agent-threads:clear-history',
  setBrowserProfile: 'agent-threads:set-browser-profile',
  changed: 'agent-threads:changed'
} as const;

export const browserIpcChannels = {
  externalState: 'browser:external-state',
  externalStateChanged: 'browser:external-state-changed',
  openExternal: 'browser:open-external',
  disconnectExternal: 'browser:disconnect-external',
  detectProfiles: 'browser:detect-profiles',
  listProfiles: 'browser:list-profiles',
  importProfile: 'browser:import-profile',
  removeProfile: 'browser:remove-profile',
  show: 'browser:show',
  hide: 'browser:hide',
  navigate: 'browser:navigate',
  newTab: 'browser:new-tab',
  selectTab: 'browser:select-tab',
  closeTab: 'browser:close-tab',
  goBack: 'browser:go-back',
  goForward: 'browser:go-forward',
  reload: 'browser:reload',
  stateChanged: 'browser:state-changed'
} as const;

export const agentMessagesIpcChannels = {
  list: 'agent-messages:list',
  listDirect: 'agent-messages:list-direct',
  listTimeline: 'agent-messages:list-timeline',
  listDirectTimeline: 'agent-messages:list-direct-timeline',
  countFileLines: 'agent-messages:count-file-lines'
} as const;

export type CountFileLinesInput = {
  cwd: string;
  path: string;
};

export const agentChatIpcChannels = {
  send: 'agent-chat:send',
  stop: 'agent-chat:stop',
  pauseComputerUse: 'agent-chat:pause-computer-use',
  resumeComputerUse: 'agent-chat:resume-computer-use',
  getActiveRunEvent: 'agent-chat:get-active-run-event',
  listRunEvents: 'agent-chat:list-run-events',
  answerQuestion: 'agent-chat:answer-question',
  listPendingQuestions: 'agent-chat:list-pending-questions',
  runEvent: 'agent-chat:run-event'
} as const;

export const localFilesIpcChannels = {
  pick: 'local-files:pick',
  pickDirectory: 'local-files:pick-directory',
  describe: 'local-files:describe',
  open: 'local-files:open',
  openTerminal: 'local-files:open-terminal'
} as const;

export const codexIpcChannels = {
  getDefaults: 'codex:get-defaults',
  getStatus: 'codex:get-status',
  getModelCatalog: 'codex:get-model-catalog',
  signIn: 'codex:sign-in'
} as const;

export const quickAddIpcChannels = {
  open: 'quick-add:open'
} as const;

export const mainWindowIpcChannels = {
  setSidebarVisible: 'main-window:set-sidebar-visible',
  toggleSidebar: 'main-window:toggle-sidebar',
  openRoute: 'main-window:open-route'
} as const;

export const notchIpcChannels = {
  getLayoutMetrics: 'notch:get-layout-metrics',
  setVisible: 'notch:set-visible',
  setMouseEvents: 'notch:set-mouse-events',
  setKeyboardFocus: 'notch:set-keyboard-focus',
  notify: 'notch:notify',
  openDony: 'notch:open-dony',
  openRequested: 'notch:open-requested',
  quickAddOpen: 'notch:quick-add-open',
  quickAddDismiss: 'notch:quick-add-dismiss',
  layoutMetricsChanged: 'notch:layout-metrics-changed',
  setQuickAddActive: 'notch:set-quick-add-active'
} as const;

export const taskEntryIpcChannels = {
  startRoot: 'task-entry:start-root'
} as const;

export const settingsIpcChannels = {
  get: 'settings:get',
  update: 'settings:update',
  pickPresentationReferenceFiles: 'settings:pick-presentation-reference-files',
  addPresentationReferenceFiles: 'settings:add-presentation-reference-files',
  removePresentationReferenceFile:
    'settings:remove-presentation-reference-file',
  getDefaultAiProviderStatus: 'settings:get-default-ai-provider-status',
  getCuaStatus: 'settings:get-cua-status',
  setupComputerUse: 'settings:setup-computer-use',
  listComputerUseAllowedApps: 'settings:list-computer-use-allowed-apps',
  removeComputerUseAllowedApp: 'settings:remove-computer-use-allowed-app',
  openDataFolder: 'settings:open-data-folder',
  openRequested: 'settings:open-requested'
} as const;

export const authIpcChannels = {
  getSession: 'auth:get-session',
  startSignIn: 'auth:start-sign-in',
  signOut: 'auth:sign-out',
  changed: 'auth:changed'
} as const;

export const onboardingIpcChannels = {
  complete: 'onboarding:complete'
} as const;

export const connectorsIpcChannels = {
  list: 'connectors:list',
  connect: 'connectors:connect',
  refresh: 'connectors:refresh',
  setEnabled: 'connectors:set-enabled',
  disconnect: 'connectors:disconnect'
} as const;

export const repliesIpcChannels = {
  getSnapshot: 'replies:get-snapshot',
  syncNow: 'replies:sync-now',
  updateDraft: 'replies:update-draft',
  dismiss: 'replies:dismiss',
  send: 'replies:send',
  startTask: 'replies:start-task',
  changed: 'replies:changed'
} as const;

export const memoryIpcChannels = {
  getSnapshot: 'memory:get-snapshot',
  createSpace: 'memory:create-space',
  attachSpace: 'memory:attach-space',
  setActiveSpace: 'memory:set-active-space',
  detachSpace: 'memory:detach-space',
  readDocument: 'memory:read-document',
  saveDocument: 'memory:save-document',
  search: 'memory:search',
  remember: 'memory:remember',
  acceptProposal: 'memory:accept-proposal',
  rejectProposal: 'memory:reject-proposal',
  openFolder: 'memory:open-folder',
  initializeGit: 'memory:initialize-git',
  changed: 'memory:changed'
} as const;

export interface TasksApi {
  list(): Promise<TaskTree[]>;
  create(input: CreateTaskInput): Promise<Task>;
  importScreenshot(input: TaskScreenshotImportInput): Promise<Task[]>;
  importText(input: TaskTextImportInput): Promise<Task[]>;
  reorder(input: ReorderTasksInput): Promise<TaskTree[]>;
  update(id: string, patch: UpdateTaskPatch): Promise<Task>;
  toggle(id: string): Promise<Task>;
  delete(id: string): Promise<void>;
  acceptProactiveSuggestion(id: string): Promise<Task>;
  dismissProactiveSuggestion(id: string): Promise<void>;
  retryProactivePlanning(id: string): Promise<Task>;
  answerProactiveQuestion(
    id: string,
    response: AgentQuestionResponse
  ): Promise<Task>;
  listAgentResults(): Promise<HomeTaskAgentResult[]>;
  acceptAgentResult(id: string): Promise<Task>;
  requestAgentResultChanges(
    id: string,
    feedback: string
  ): Promise<AgentChatSendResult>;
  dismissAgentResult(id: string): Promise<void>;
  clearAgentResults(): Promise<void>;
  openTaskOutput(outputId: string): Promise<void>;
  openTaskResultLink(url: string): Promise<void>;
  deleteTaskOutput(outputId: string): Promise<void>;
  setTodoRouteActive(active: boolean): Promise<void>;
  onChanged(listener: () => void): () => void;
}

export interface TaskSuggestionsApi {
  getSnapshot(): Promise<TaskSuggestionsSnapshot>;
  syncNow(): Promise<TaskSuggestionsSnapshot>;
  accept(id: string): Promise<Task>;
  addToList(id: string): Promise<Task>;
  dismiss(id: string): Promise<void>;
  onChanged(listener: () => void): () => void;
}

export interface ContextExtractorApi {
  getSnapshot(): Promise<ContextExtractorSnapshot>;
  syncNow(): Promise<ContextExtractorSnapshot>;
  onChanged(listener: () => void): () => void;
}

export interface AgentsApi {
  list(): Promise<Agent[]>;
  get(id: string): Promise<Agent>;
  create(input: CreateAgentInput): Promise<Agent>;
  generateWelcome(
    id: string,
    context: AgentWelcomeContextInput
  ): Promise<Agent>;
  update(id: string, patch: UpdateAgentPatch): Promise<Agent>;
  delete(id: string): Promise<void>;
}

export interface ProvidersApi {
  list(): Promise<ProviderConfig[]>;
  get(id: string): Promise<ProviderConfig>;
  create(input: CreateProviderConfigInput): Promise<ProviderConfig>;
  update(id: string, patch: UpdateProviderConfigPatch): Promise<ProviderConfig>;
  testDraft(input: ProviderConfigDraft): Promise<ProviderConnectionCheck>;
  getDefaults(providerType: ProviderType): Promise<ProviderConfigDefaults>;
  configure(
    input: ProviderConfigDraft,
    credential?: string | null
  ): Promise<ProviderConfig>;
  models(input: ProviderConfigDefaults): Promise<ProviderModelOption[]>;
  signIn(input: ProviderConfigDefaults): Promise<void>;
}

export interface AgentThreadsApi {
  get(id: string): Promise<AgentThread>;
  getDefault(agentId: string): Promise<AgentThread>;
  getLatest(agentId: string): Promise<AgentThread>;
  getCurrent(agentId: string): Promise<AgentThread | null>;
  create(input: CreateAgentThreadInput): Promise<AgentThread>;
  listTaskThreads(): Promise<AgentThread[]>;
  listRecent(limit?: number): Promise<AgentThreadSummary[]>;
  search(query: string): Promise<AgentThread[]>;
  archive(threadId: string): Promise<AgentThread>;
  markViewed(threadId: string, viewedAt?: string): Promise<AgentThread>;
  deleteHistoryThread(threadId: string): Promise<void>;
  clearAgentHistory(agentId: string): Promise<string[]>;
  clearHistory(): Promise<void>;
  setBrowserProfile(
    threadId: string,
    profileId: string | null
  ): Promise<AgentThread>;
  onChanged(listener: () => void): () => void;
}

export interface BrowserApi {
  externalState(threadId: string): Promise<ExternalBrowserState>;
  openExternal(threadId: string): Promise<ExternalBrowserConnection>;
  onExternalStateChanged(
    listener: (state: ExternalBrowserState) => void
  ): () => void;
  disconnectExternal(threadId: string): Promise<void>;
  detectProfiles(): Promise<DetectedBrowserProfile[]>;
  listProfiles(): Promise<BrowserProfile[]>;
  importProfile(input: ImportBrowserProfileInput): Promise<BrowserProfile>;
  removeProfile(id: string): Promise<void>;
  show(threadId: string, bounds: BrowserBounds): Promise<BrowserViewState>;
  hide(threadId: string): Promise<void>;
  navigate(threadId: string, url: string): Promise<BrowserViewState>;
  newTab(threadId: string): Promise<BrowserViewState>;
  selectTab(threadId: string, tabId: string): Promise<BrowserViewState>;
  closeTab(threadId: string, tabId: string): Promise<BrowserViewState>;
  goBack(threadId: string): Promise<BrowserViewState>;
  goForward(threadId: string): Promise<BrowserViewState>;
  reload(threadId: string): Promise<BrowserViewState>;
  onStateChanged(listener: (state: BrowserViewState) => void): () => void;
}

export interface AgentMessagesApi {
  list(threadId: string): Promise<AgentMessage[]>;
  listDirect(agentId: string): Promise<AgentMessage[]>;
  listTimeline(threadId: string): Promise<CodexTimelineEvent[]>;
  listDirectTimeline(agentId: string): Promise<CodexTimelineEvent[]>;
  countFileLines(input: CountFileLinesInput): Promise<number | null>;
}

export interface AgentChatApi {
  send(input: AgentChatSendInput): Promise<AgentChatSendResult>;
  stop(runId: string): Promise<CodexRun>;
  pauseComputerUse(runId: string): Promise<void>;
  resumeComputerUse(runId: string): Promise<void>;
  getActiveRunEvent(threadId: string): Promise<AgentChatRunEvent | null>;
  listRunEvents(runIds: string[]): Promise<AgentChatRunEvent[]>;
  listPendingQuestions(): Promise<PendingAgentQuestion[]>;
  answerQuestion(
    questionId: string,
    response: AgentQuestionResponse
  ): Promise<AgentChatSendResult | null>;
  onRunEvent(listener: (event: AgentChatRunEvent) => void): () => void;
}

export interface LocalFilesApi {
  getPathForFile(file: unknown): string;
  pick(): Promise<LocalFileAttachment[]>;
  pickDirectory(input?: PickLocalDirectoryInput): Promise<string | null>;
  describe(paths: string[]): Promise<LocalFileAttachment[]>;
  open(path: string): Promise<void>;
  openTerminal(input: OpenTerminalInput): Promise<void>;
}

export type CodexConfigDefaults = {
  command: string;
  executionMode: CodexExecutionMode;
};

export type CodexStatus = {
  command: string;
  status: ProviderStatus;
  version: string | null;
  loginStatus: string | null;
  lastCheckedAt: string;
  lastError: string | null;
};

export type CodexModelCatalog = {
  models: ProviderModelOption[];
  source: 'runtime' | 'cache' | 'fallback';
  refreshedAt: string | null;
  lastError: string | null;
};

export interface CodexApi {
  getDefaults(): Promise<CodexConfigDefaults>;
  getStatus(command?: string): Promise<CodexStatus>;
  getModelCatalog(): Promise<CodexModelCatalog>;
  signIn(): Promise<CodexStatus>;
}

export type QuickAddOpenListener = () => void;

export interface QuickAddApi {
  onOpenRequested(listener: QuickAddOpenListener): () => void;
}

export interface MainWindowApi {
  setSidebarVisible(visible: boolean, animate: boolean): Promise<void>;
  onToggleSidebarRequested(listener: () => void): () => void;
  onOpenRouteRequested(listener: (route: string) => void): () => void;
}

export interface NotchApi {
  getLayoutMetrics(): Promise<NotchLayoutMetrics>;
  setVisible(visible: boolean): Promise<void>;
  setMouseEvents(enabled: boolean): Promise<void>;
  setKeyboardFocus(enabled: boolean): Promise<void>;
  notify(): Promise<void>;
  openDony(): Promise<void>;
  setQuickAddActive(active: boolean): Promise<void>;
  onOpenRequested(listener: () => void): () => void;
  onQuickAddOpenRequested(listener: () => void): () => void;
  onQuickAddDismissRequested(listener: () => void): () => void;
  onLayoutMetricsChanged(
    listener: (metrics: NotchLayoutMetrics) => void
  ): () => void;
}

export interface NotchLayoutMetrics {
  compactHeight: number;
  compactWidth: number;
}

export type TaskEntryStartListener = () => void;

export interface TaskEntryApi {
  onStartRootRequested(listener: TaskEntryStartListener): () => void;
}

export interface SettingsApi {
  get(): Promise<AppSettingsSnapshot>;
  update(input: UpdateAppSettingsInput): Promise<AppSettingsSnapshot>;
  pickPresentationReferenceFiles(): Promise<AppSettingsSnapshot>;
  addPresentationReferenceFiles(paths: string[]): Promise<AppSettingsSnapshot>;
  removePresentationReferenceFile(id: string): Promise<AppSettingsSnapshot>;
  getDefaultAiProviderStatus(): Promise<ProviderConnectionCheck>;
  getCuaStatus(): Promise<CuaDevStatus>;
  setupComputerUse(): Promise<CuaDevStatus>;
  listComputerUseAllowedApps(): Promise<ComputerUseAllowedApp[]>;
  removeComputerUseAllowedApp(id: string): Promise<ComputerUseAllowedApp[]>;
  openDataFolder(): Promise<void>;
  onOpenRequested(listener: () => void): () => void;
}

export interface AuthApi {
  getSession(): Promise<AuthSessionSnapshot>;
  startSignIn(): Promise<AuthStartResult>;
  signOut(): Promise<AuthSessionSnapshot>;
  onChanged(listener: (snapshot: AuthSessionSnapshot) => void): () => void;
}

export interface OnboardingApi {
  complete(): Promise<void>;
}

export interface ConnectorsApi {
  list(): Promise<ConnectorsStatus>;
  connect(toolkit: string): Promise<ConnectorConnectResult>;
  refresh(connectedAccountId: string): Promise<ConnectorRefreshResult>;
  setEnabled(connectedAccountId: string, enabled: boolean): Promise<void>;
  disconnect(connectedAccountId: string): Promise<void>;
}

export interface RepliesApi {
  getSnapshot(): Promise<RepliesSnapshot>;
  syncNow(): Promise<RepliesSnapshot>;
  updateDraft(input: UpdateReplyDraftInput): Promise<ReplySuggestion>;
  dismiss(id: string): Promise<ReplySuggestion>;
  send(id: string): Promise<ReplySuggestion>;
  startTask(input: StartReplyTaskInput): Promise<StartReplyTaskResult>;
  onChanged(listener: () => void): () => void;
}

export interface MemoryApi {
  getSnapshot(): Promise<MemorySnapshot>;
  createSpace(input: CreateMemorySpaceInput): Promise<MemorySnapshot>;
  attachSpace(input: AttachMemorySpaceInput): Promise<MemorySnapshot>;
  setActiveSpace(id: string): Promise<MemorySnapshot>;
  detachSpace(id: string): Promise<MemorySnapshot>;
  readDocument(path: string): Promise<MemoryDocument>;
  saveDocument(input: SaveMemoryDocumentInput): Promise<MemoryDocument>;
  search(query: string): Promise<MemorySearchResult[]>;
  remember(input: RememberMemoryInput): Promise<MemoryDocument>;
  acceptProposal(id: string, content?: string): Promise<MemorySnapshot>;
  rejectProposal(id: string): Promise<MemorySnapshot>;
  openFolder(): Promise<void>;
  initializeGit(): Promise<MemorySnapshot>;
  onChanged(listener: () => void): () => void;
}
