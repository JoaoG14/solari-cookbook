import { describe, expect, it } from 'vitest';

import {
  agentChatSendResultSchema,
  agentQuestionResponseSchema,
  agentQuestionSchema,
  agentResponseLanguageInstruction,
  agentResponseLanguageOptions,
  agentResponseStyleInstructions,
  agentChatTargetSchema,
  authSessionSnapshotSchema,
  connectorsStatusSchema,
  connectorRefreshResultSchema,
  createAgentInputSchema,
  createProviderConfigInputSchema,
  createTaskInputSchema,
  nativeAgentLocalToolNameSchema,
  noEmDashWritingInstruction,
  normalizeProactiveSuggestionLabel,
  providerCatalog,
  providerDefaultModelByType,
  providerModelOptions,
  reorderTasksInputSchema,
  taskScreenshotImportInputSchema,
  taskOutputDesignInstructions,
  taskOutputDesignOptions,
  taskOutputDesignSchema,
  taskTreeSchema,
  updateAgentPatchSchema,
  updateProviderConfigPatchSchema,
  updateTaskPatchSchema
} from './index';

describe('task domain schemas', () => {
  it('normalizes proactive suggestion labels to one action word', () => {
    expect(normalizeProactiveSuggestionLabel('Plan hiring with AI')).toBe(
      'Plan with AI'
    );
    expect(
      normalizeProactiveSuggestionLabel('Research candidates with AI')
    ).toBe('Research with AI');
    expect(normalizeProactiveSuggestionLabel('write with AI')).toBe(
      'Write with AI'
    );
    expect(normalizeProactiveSuggestionLabel(null)).toBe('Do with AI');
  });

  it('keeps agent responses in the language of the latest request', () => {
    expect(agentResponseStyleInstructions).toContain(
      'Match the language of the latest user request. Use another language only when the user explicitly asks for it.'
    );
  });

  it('offers automatic and fixed agent response languages', () => {
    expect(agentResponseLanguageOptions[0]).toEqual({
      value: 'automatic',
      label: 'Automatic'
    });
    expect(agentResponseLanguageOptions).toContainEqual({
      value: 'pt-BR',
      label: 'Portuguese (Brazil)'
    });
    expect(agentResponseLanguageInstruction('pt-BR')).toContain(
      'Write the response in Brazilian Portuguese'
    );
  });

  it('prevents em dashes in AI-written text', () => {
    expect(noEmDashWritingInstruction).toContain('Never use em dashes');
    expect(agentResponseStyleInstructions).toContain(
      noEmDashWritingInstruction
    );
    expect(agentResponseStyleInstructions).toContain(
      'This brevity does not limit requested deliverables or published task outputs'
    );
  });

  it('exposes every selectable task output design with instructions', () => {
    expect(taskOutputDesignOptions.map((option) => option.value)).toEqual([
      'dony',
      'elevenlabs',
      'editorial-cards',
      'acctual',
      'hatch'
    ]);
    expect(taskOutputDesignOptions.map((option) => option.label)).toEqual([
      'Quiet Neutral',
      'Warm Editorial',
      'Editorial Cards',
      'Crisp Document',
      'Pastel Zine'
    ]);
    expect(taskOutputDesignSchema.parse('editorial-cards')).toBe(
      'editorial-cards'
    );
    expect(taskOutputDesignInstructions('editorial-cards')).toContain(
      '#f5f3f1'
    );
    expect(taskOutputDesignInstructions('editorial-cards')).toContain(
      'never use general web-search result URLs'
    );
    expect(taskOutputDesignInstructions('editorial-cards')).toContain(
      'prefer a useful breadth of well-supported items'
    );
    expect(taskOutputDesignInstructions('editorial-cards')).toContain(
      'Never pad a list or invent entries'
    );
    expect(taskOutputDesignInstructions('editorial-cards')).toContain(
      'Keep the visual design simple and restrained'
    );
    expect(taskOutputDesignSchema.safeParse('gsap').success).toBe(false);
  });

  it('accepts nested task trees', () => {
    const parsed = taskTreeSchema.parse({
      id: crypto.randomUUID(),
      title: 'Parent task',
      status: 'todo',
      parentTaskId: null,
      sortOrder: 0,
      notes: null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      completedAt: null,
      deletedAt: null,
      children: [
        {
          id: crypto.randomUUID(),
          title: 'Child task',
          status: 'done',
          parentTaskId: crypto.randomUUID(),
          sortOrder: 0,
          notes: null,
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
          completedAt: new Date().toISOString(),
          deletedAt: null,
          children: []
        }
      ]
    });

    expect(parsed.children).toHaveLength(1);
  });

  it('rejects empty task titles on create and update', () => {
    expect(() => createTaskInputSchema.parse({ title: '   ' })).toThrow();
    expect(() => updateTaskPatchSchema.parse({ title: '   ' })).toThrow();
  });

  it('accepts date-only task due dates and rejects invalid calendar dates', () => {
    expect(
      createTaskInputSchema.parse({
        title: 'File quarterly report',
        dueDate: '2026-09-30'
      }).dueDate
    ).toBe('2026-09-30');
    expect(updateTaskPatchSchema.parse({ dueDate: null }).dueDate).toBeNull();
    expect(() =>
      updateTaskPatchSchema.parse({ dueDate: '2026-02-30' })
    ).toThrow('Due date must be a valid calendar date.');
    expect(() =>
      updateTaskPatchSchema.parse({ dueDate: '09/30/2026' })
    ).toThrow('Due date must use YYYY-MM-DD.');
  });

  it('requires unique task IDs when reordering siblings', () => {
    const taskId = crypto.randomUUID();

    expect(() =>
      reorderTasksInputSchema.parse({
        parentTaskId: null,
        taskIds: [taskId, taskId]
      })
    ).toThrow();
  });

  it('accepts supported screenshots and rejects other file types', () => {
    expect(
      taskScreenshotImportInputSchema.parse({
        name: 'todos.png',
        mimeType: 'image/png',
        base64: 'aW1hZ2U='
      })
    ).toMatchObject({ mimeType: 'image/png' });
    expect(() =>
      taskScreenshotImportInputSchema.parse({
        name: 'todos.gif',
        mimeType: 'image/gif',
        base64: 'aW1hZ2U='
      })
    ).toThrow();
  });
});

describe('agent and provider schemas', () => {
  it('accepts agent creation with a linked provider config', () => {
    const providerConfigId = crypto.randomUUID();

    const parsed = createAgentInputSchema.parse({
      name: 'Build bot',
      emoji: '🛠️',
      color: '#72f868',
      instructions: 'Ship changes without touching storage.',
      providerConfigId,
      cwd: '/tmp/workspace',
      modelOverride: 'gpt-5.5',
      codexCommand: 'codex',
      codexExecutionMode: 'full_auto'
    });

    expect(parsed.providerConfigId).toBe(providerConfigId);
    expect(parsed).not.toHaveProperty('role');
  });

  it('accepts provider config creation and updates with status metadata', () => {
    const created = createProviderConfigInputSchema.parse({
      name: 'Local Codex',
      providerType: 'codex_local',
      command: 'codex',
      defaultModel: 'gpt-5.5'
    });

    const updated = updateProviderConfigPatchSchema.parse({
      status: 'ready',
      lastCheckedAt: new Date().toISOString(),
      lastError: null
    });

    expect(created.providerType).toBe('codex_local');
    expect(updated.status).toBe('ready');
  });

  it('requires non-empty agent and provider update patches', () => {
    expect(() => updateAgentPatchSchema.parse({})).toThrow();
    expect(() => updateProviderConfigPatchSchema.parse({})).toThrow();
  });

  it('accepts agent chat payloads with a persisted transcript', () => {
    const now = new Date().toISOString();
    const parsed = agentChatSendResultSchema.parse({
      thread: {
        id: crypto.randomUUID(),
        agentId: crypto.randomUUID(),
        title: 'Default thread',
        isDefault: true,
        codexSessionId: null,
        createdAt: now,
        updatedAt: now,
        archivedAt: null
      },
      messages: [
        {
          id: crypto.randomUUID(),
          threadId: crypto.randomUUID(),
          role: 'user',
          content: 'Ship Step 3',
          status: 'complete',
          createdAt: now,
          updatedAt: now,
          providerMetadata: null
        }
      ],
      run: {
        id: crypto.randomUUID(),
        threadId: crypto.randomUUID(),
        assistantMessageId: crypto.randomUUID(),
        status: 'running',
        command: 'codex',
        cwd: '/tmp/workspace',
        model: 'gpt-5.5',
        profile: null,
        executionMode: 'full_auto',
        codexSessionId: null,
        startedAt: now,
        completedAt: null,
        error: null
      }
    });

    expect(parsed.messages[0]?.role).toBe('user');
  });

  it('requires explicit agent chat targets', () => {
    const agentId = crypto.randomUUID();
    const threadId = crypto.randomUUID();

    expect(agentChatTargetSchema.parse({ type: 'latest', agentId })).toEqual({
      type: 'latest',
      agentId
    });
    expect(
      agentChatTargetSchema.parse({ type: 'thread', agentId, threadId })
    ).toEqual({
      type: 'thread',
      agentId,
      threadId
    });
    expect(() =>
      agentChatTargetSchema.parse({ type: 'unknown', agentId })
    ).toThrow();
  });

  it('exposes Dony, Codex, and Claude Code as enabled providers', () => {
    expect(providerCatalog).toEqual([
      expect.objectContaining({ type: 'dony_native', isEnabled: true }),
      expect.objectContaining({ type: 'codex_local', isEnabled: true }),
      expect.objectContaining({ type: 'claude_code_local', isEnabled: true })
    ]);
  });

  it('matches the current ChatGPT-plan model catalog', () => {
    expect(
      providerModelOptions.codex_local.map((option) => option.value)
    ).toEqual([
      'gpt-5.6-sol',
      'gpt-5.6-terra',
      'gpt-5.6-luna',
      'gpt-5.5',
      'gpt-5.4',
      'gpt-5.4-mini',
      'gpt-5.3-codex-spark'
    ]);
    expect(providerDefaultModelByType.codex_local).toBe('gpt-5.6-terra');
  });
});

describe('auth schemas', () => {
  it('requires signed-in sessions to include a user', () => {
    expect(
      authSessionSnapshotSchema.parse({
        status: 'signed_in',
        user: {
          id: 'user_123',
          email: 'user@dony.local',
          name: 'Dony User',
          avatarUrl: null
        }
      })
    ).toEqual({
      status: 'signed_in',
      user: {
        id: 'user_123',
        email: 'user@dony.local',
        name: 'Dony User',
        avatarUrl: null
      }
    });

    expect(() =>
      authSessionSnapshotSchema.parse({
        status: 'signed_in',
        user: null
      })
    ).toThrow();
  });
});

describe('connector schemas', () => {
  it('accepts connector status snapshots and native connector tools', () => {
    expect(
      connectorsStatusSchema.parse({
        enabled: true,
        disabledReason: null,
        toolkits: [
          {
            slug: 'gmail',
            name: 'Gmail',
            logoUrl: 'https://logos.composio.dev/api/gmail',
            isConnected: true,
            status: 'ACTIVE',
            connectedAccountId: 'ca_123',
            authConfigId: 'ac_123'
          }
        ]
      })
    ).toEqual(
      expect.objectContaining({
        enabled: true
      })
    );
    expect(nativeAgentLocalToolNameSchema.parse('connector_use')).toBe(
      'connector_use'
    );
    expect(nativeAgentLocalToolNameSchema.parse('ask_user')).toBe('ask_user');
    expect(
      connectorRefreshResultSchema.parse({
        url: 'https://connect.composio.dev/refresh'
      })
    ).toEqual({ url: 'https://connect.composio.dev/refresh' });
  });
});

describe('agent question schemas', () => {
  it('accepts resource questions and attached-file answers', () => {
    const question = agentQuestionSchema.parse({
      id: crypto.randomUUID(),
      runId: crypto.randomUUID(),
      threadId: crypto.randomUUID(),
      header: 'Weekly report',
      question: 'Please provide last week’s report.',
      options: [],
      allowCustomAnswer: true,
      multiple: false,
      responseKind: 'resource',
      questions: [
        {
          id: 'report',
          header: 'Weekly report',
          question: 'Please provide last week’s report.',
          options: [],
          allowCustomAnswer: true,
          multiple: false,
          responseKind: 'resource'
        }
      ],
      createdAt: new Date().toISOString()
    });

    expect(question.questions[0]?.responseKind).toBe('resource');
    expect(
      agentQuestionResponseSchema.parse({
        action: 'accept',
        answers: [],
        attachments: [{ path: '/tmp/workspace/weekly-report.pdf' }]
      })
    ).toEqual({
      action: 'accept',
      answers: [],
      attachments: [{ path: '/tmp/workspace/weekly-report.pdf' }]
    });
  });
});
