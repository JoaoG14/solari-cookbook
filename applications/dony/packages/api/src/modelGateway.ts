import { randomUUID } from 'node:crypto';

import {
  buildAgentResponseStyleInstructions,
  localToolDescriptions,
  type OpenAIFunctionToolDefinition,
  publishedTaskOutputResponseInstructions,
  taskOutputDesignInstructions,
  type NativeAgentLocalToolCall,
  type NativeAgentLocalToolName,
  type NativeAgentLocalToolResult,
  type NativeAgentRunRequest,
  type NativeAgentRunResponse,
  type NativeAgentStreamEvent,
  type NativeAgentTimelineEventDraft
} from '@dony/domain';

import { assertNever, config } from './config';

type ModelGateway = {
  run(
    request: NativeAgentRunRequest,
    signal: AbortSignal
  ): Promise<NativeAgentRunResponse>;
  runStream(
    request: NativeAgentRunRequest,
    signal: AbortSignal,
    runtime?: ModelGatewayRuntime
  ): AsyncIterable<NativeAgentStreamEvent>;
};

type ModelGatewayRuntime = {
  waitForLocalToolResult(callId: string): Promise<NativeAgentLocalToolResult>;
};

type OpenAIResponseContent = {
  type?: unknown;
  text?: unknown;
};

type OpenAIResponseOutput = {
  id?: unknown;
  type?: unknown;
  content?: unknown;
  name?: unknown;
  arguments?: unknown;
  call_id?: unknown;
};

type OpenAIResponseBody = {
  id?: unknown;
  output_text?: unknown;
  output?: unknown;
  error?: unknown;
};

type OpenAIStreamEvent = {
  type?: unknown;
  response?: unknown;
  delta?: unknown;
  error?: unknown;
};


type OpenAIRequestBody = {
  model: string;
  service_tier?: NativeAgentRunRequest['modelServiceTier'];
  instructions?: string;
  input: unknown;
  text?: {
    format: {
      type: 'json_schema';
      name: 'dony_app_ai';
      schema: Record<string, unknown>;
      strict: true;
    };
  };
  tools?: OpenAIFunctionToolDefinition[];
  previous_response_id?: string;
  stream?: true;
};

const donySystemPrompt = [
  'You are Dony, a first-party desktop agent operated through the Dony backend.',
  'Answer as the selected agent using the agent profile and conversation context.',
  'The user cannot choose the underlying AI provider; Dony decides that server-side.',
  'Use local tool results as the source of truth for desktop and filesystem actions. Do not claim you moved files, edited calendars, sent messages, or used local apps unless a tool result says so.',
  'When local tools are available, call them through the provided function tools only. Never write raw tool call JSON, <tool_call> blocks, functions.* text, or pretend tool outputs in assistant text.',
  [
    'Autonomy policy:',
    "- Act directly when the user's goal is clear.",
    '- Infer conventional, low-risk details instead of asking about every preference.',
    '- Inspect available context first, then choose the smallest sensible and reversible action.',
    "- Do not ask for confirmation for steps directly implied by the user's request.",
    '- Ask only when a missing decision would significantly change the intended outcome, or before an irreversible, destructive, sensitive, costly, or external action.',
    '- Never invent facts, requirements, destinations, recipients, or content that cannot be reasonably inferred from the request or environment.',
    '- When uncertain, preserve existing data and choose the option that is easiest to undo.',
    '- When ask_user is needed, use it instead of ending the run with a question in assistant text.',
    '- When the user needs to provide a file or link, set responseKind to resource and do not offer placeholder choices such as "I will provide it".'
  ].join('\n'),
  'When connector_use is available, use it for connected cloud apps instead of browser automation. Available plugins can include Gmail, Google Calendar, Google Drive, Google Docs, Google Sheets, Google Slides, Outlook, Microsoft Excel, Microsoft Teams, Slack, Asana, Airtable, Confluence, Zoom, Canva, Cloudflare, Figma, Granola, Hugging Face, Linear, Notion, Render, Stripe, Supabase, and Vercel.',
  'Use connector_use search_tools before execute_tool when you are not sure which Composio tool slug handles the requested app action.',
  'For connector tools that upload files, pass localFiles with one entry per file: argumentName, path, and mimeType. Omit those file arguments from argumentsJson. Dony stages the files automatically. Never put a local path in an s3key field.',
  'For emails, calendar invites, file sharing, document edits, and spreadsheet edits, draft the proposed action, then use ask_user for missing details before attempting the connector action.',
  'Once the requested desktop action appears complete, stop using tools and answer the user briefly instead of continuing to verify.',
  [
    'Computer-use policy:',
    '- Inspect before acting: use list_windows and get_window_state to find an existing relevant app/window before launching anything.',
    '- Reuse existing windows/tabs when possible. Do not open duplicate apps, browser windows, or tabs if a suitable one already exists.',
    '- Prefer fresh element_token targets from get_window_state and always include pid and window_id. element_index requires its matching snapshot_id. Use screenshot coordinates only when no useful element target exists, and do not rescale them.',
    '- Set requires_confirmation=true with a short intent before any action that sends, publishes, purchases, deletes user data, changes account/security settings, installs software, grants access, or submits credentials.',
    '- After each mutation or uncertain result, observe the same window and verify the intended change. Never blindly replay a timed-out action. Background delivery must not automatically fall back to foreground.',
    '- Action delivery alone is not proof of the intended change. Once the requested state is verified, stop calling tools and give a concise status.'
  ].join('\n'),
  'If a requested action needs unavailable connectors, explain what would be needed to complete the action.'
].join('\n');

const buildInstructions = (request: NativeAgentRunRequest): string => {
  const agentProfile = [
    `Agent name: ${request.agent.name}`,
    `Working directory: ${request.agent.cwd}`,
    `Instructions: ${request.agent.instructions.trim() || 'No extra instructions.'}`
  ].join('\n');

  const taskOutputInstructions = request.localTools?.includes(
    'publish_task_output'
  )
    ? [
        '',
        'This run originated from a Dony To-do task.',
        'If the main deliverable is a substantial summary, brief, report, analysis, comparison, plan, itinerary, or similarly useful reading artifact, publish it once with publish_task_output.',
        'Do not publish an output for code changes, short answers, routine actions, or work that is better represented by an ordinary file.',
        taskOutputDesignInstructions(request.taskOutputDesign ?? 'dony'),
        'Keep the page source-faithful, readable, and no more complex than its content.',
        publishedTaskOutputResponseInstructions
      ].join('\n')
    : '';

  const memoryInstructions = request.localTools?.includes('memory_search')
    ? [
        '',
        'Every Dony agent receives the active CONTEXT.md automatically.',
        'Use it as durable user background. Use memory_search and memory_read when you need to inspect it again.',
        'Silently use memory_write with the complete replacement content for CONTEXT.md when new durable, well-supported context should be saved.',
        'Preserve provenance. Do not store secrets, credentials, temporary chatter, generated files, or uncertain guesses.'
      ].join('\n')
    : '';

  const chatHistoryInstructions = request.localTools?.includes('chat_search')
    ? [
        '',
        'Use chat_search and chat_read only when the user explicitly refers to an earlier conversation or when missing chat context is needed to answer the current request.',
        'Search this agent by default. Search all agents only when the user clearly refers to another agent or asks for a cross-agent search.',
        'Treat chat history as user-visible conversation evidence, not as durable user context. Do not mine unrelated conversations.'
      ].join('\n')
    : '';

  const responseStyleInstructions = buildAgentResponseStyleInstructions(
    request.agentResponseLanguage ?? 'automatic'
  );

  return `${donySystemPrompt}\n${responseStyleInstructions}\n\n${agentProfile}${memoryInstructions}${chatHistoryInstructions}${taskOutputInstructions}`;
};

const buildInput = (request: NativeAgentRunRequest): unknown => {
  const transcript = request.transcript
    .map((message) => `${message.role.toUpperCase()}: ${message.content}`)
    .join('\n\n');
  const latestMessage = `USER: ${request.message}`;
  const text = transcript ? `${transcript}\n\n${latestMessage}` : latestMessage;

  if (!request.images?.length) {
    return text;
  }

  return [
    {
      role: 'user',
      content: [
        { type: 'input_text', text },
        ...request.images.map((image) => ({
          type: 'input_image',
          image_url: `data:${image.mimeType};base64,${image.base64}`,
          detail: 'high'
        }))
      ]
    }
  ];
};


const localToolDefinitions = (
  request: NativeAgentRunRequest
): OpenAIFunctionToolDefinition[] =>
  (request.localTools ?? []).map((tool) => localToolDescriptions[tool]);

const openAIRequestBody = (
  request: NativeAgentRunRequest,
  input: unknown,
  options: {
    previousResponseId?: string;
    stream?: true;
    includeTools?: boolean;
  } = {}
): OpenAIRequestBody => {
  if (config.modelGateway.type !== 'openai') {
    throw new Error('OpenAI gateway is not configured.');
  }

  const tools = options.includeTools ? localToolDefinitions(request) : [];
  const body: OpenAIRequestBody = {
    model: config.modelGateway.model,
    ...(request.modelServiceTier
      ? { service_tier: request.modelServiceTier }
      : {}),
    input
  };

  if (request.outputSchema) {
    body.text = {
      format: {
        type: 'json_schema',
        name: 'dony_app_ai',
        schema: request.outputSchema,
        strict: true
      }
    };
  }

  if (options.previousResponseId) {
    body.previous_response_id = options.previousResponseId;
  } else {
    body.instructions = buildInstructions(request);
  }

  if (tools.length > 0) {
    body.tools = tools;
  }

  if (options.stream) {
    body.stream = true;
  }

  return body;
};

const asRecord = (value: unknown): Record<string, unknown> | null =>
  value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;

const openAIErrorMessage = (body: OpenAIResponseBody): string | null => {
  const error = asRecord(body.error);
  const message = error?.message;

  return typeof message === 'string' && message.trim().length > 0
    ? message.trim()
    : null;
};

const outputTextFromContent = (
  content: OpenAIResponseContent
): string | null =>
  (content.type === 'output_text' || content.type === 'text') &&
  typeof content.text === 'string' &&
  content.text.trim().length > 0
    ? content.text
    : null;

const extractOpenAIText = (body: OpenAIResponseBody): string => {
  if (
    typeof body.output_text === 'string' &&
    body.output_text.trim().length > 0
  ) {
    return body.output_text;
  }

  const output = Array.isArray(body.output) ? body.output : [];
  const text = output
    .flatMap((item: OpenAIResponseOutput) =>
      Array.isArray(item.content) ? item.content : []
    )
    .map((item: OpenAIResponseContent) => outputTextFromContent(item))
    .filter((item): item is string => item !== null)
    .join('\n')
    .trim();

  if (text.length === 0) {
    throw new Error('Model gateway returned an empty response.');
  }

  return text;
};

const looksLikeRawToolCallText = (content: string): boolean =>
  /<tool_call\b|<\/tool_call>|<\|[^>]*functions\.|to=functions\.|functions\.[a-z_]+\s*\(|"name"\s*:\s*"functions\.|"recipient"\s*:\s*"functions\./i.test(
    content
  );

const assertNoRawToolCallText = (content: string): void => {
  if (looksLikeRawToolCallText(content)) {
    throw new Error(
      'The model returned raw tool-call text instead of a Dony tool call. Please retry the task.'
    );
  }
};

const localToolCallsFromOutput = (
  body: OpenAIResponseBody,
  request: NativeAgentRunRequest
): NativeAgentLocalToolCall[] => {
  const availableTools = new Set(request.localTools ?? []);
  const output = Array.isArray(body.output) ? body.output : [];

  return output.flatMap((item: OpenAIResponseOutput) => {
    if (
      item.type !== 'function_call' ||
      typeof item.name !== 'string' ||
      !availableTools.has(item.name as NativeAgentLocalToolName)
    ) {
      return [];
    }

    const callId =
      typeof item.call_id === 'string'
        ? item.call_id
        : typeof item.id === 'string'
          ? item.id
          : null;

    if (!callId) {
      return [];
    }

    return [
      {
        id: callId,
        name: item.name as NativeAgentLocalToolName,
        arguments:
          typeof item.arguments === 'string'
            ? JSON.parse(item.arguments)
            : item.arguments
      }
    ];
  });
};

const textDeltas = (content: string): string[] =>
  content.match(/.{1,80}(\s|$)/g) ?? [content];

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

async function* openAIStreamEvents(
  response: Response
): AsyncIterable<OpenAIStreamEvent> {
  if (!response.body) {
    throw new Error('OpenAI gateway returned an empty stream.');
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  const parseChunk = (chunk: string): OpenAIStreamEvent | null => {
    const data = chunk
      .split(/\r?\n/)
      .filter((line) => line.startsWith('data:'))
      .map((line) => line.slice('data:'.length).trim())
      .join('\n');

    if (data.length === 0 || data === '[DONE]') {
      return null;
    }

    return JSON.parse(data) as OpenAIStreamEvent;
  };

  while (true) {
    const { done, value } = await reader.read();
    buffer += decoder.decode(value, { stream: !done });
    const chunks = buffer.split(/\n\n/);
    buffer = chunks.pop() ?? '';

    for (const chunk of chunks) {
      const event = parseChunk(chunk);

      if (event) {
        yield event;
      }
    }

    if (done) {
      const event = parseChunk(buffer);

      if (event) {
        yield event;
      }
      break;
    }
  }
}

const standardPersonalFolderPath = (message: string): string | null => {
  if (/\bdesktop\b/i.test(message)) {
    return '~/Desktop';
  }

  if (/\bdownloads?\b/i.test(message)) {
    return '~/Downloads';
  }

  if (/\bdocuments?\b/i.test(message)) {
    return '~/Documents';
  }

  return null;
};

class DevModelGateway implements ModelGateway {
  public async run(
    request: NativeAgentRunRequest
  ): Promise<NativeAgentRunResponse> {
    const modelLabel = request.model?.trim() || 'Dony Auto';

    return {
      content: [
        `Dony received your task for ${request.agent.name}.`,
        '',
        `Native provider is connected through the Dony backend using ${modelLabel}.`,
        'Set DONY_MODEL_GATEWAY=openai to route this endpoint through the model gateway.'
      ].join('\n'),
      timelineEvents: [
        {
          kind: 'status',
          title: 'Dony backend reached',
          detail:
            'Native provider request completed by the development gateway.',
          metadata: {
            threadId: request.threadId,
            transcriptLength: request.transcript.length
          }
        }
      ]
    };
  }

  public async *runStream(
    request: NativeAgentRunRequest,
    _signal: AbortSignal,
    runtime?: ModelGatewayRuntime
  ): AsyncIterable<NativeAgentStreamEvent> {
    const personalFolderPath = standardPersonalFolderPath(request.message);

    if (
      runtime &&
      request.runId &&
      request.localTools?.includes('filesystem_list_directory') &&
      personalFolderPath
    ) {
      const call: NativeAgentLocalToolCall = {
        id: randomUUID(),
        name: 'filesystem_list_directory',
        arguments: {
          path: personalFolderPath
        }
      };

      yield { type: 'local_tool_call', call };
      const result = await runtime.waitForLocalToolResult(call.id);
      yield { type: 'local_tool_result', result };
    }

    const response = await this.run(request);

    for (const event of response.timelineEvents ?? []) {
      yield { type: 'timeline', event };
    }

    for (const delta of textDeltas(response.content)) {
      await sleep(20);
      yield { type: 'assistant_delta', delta };
    }

    yield {
      type: 'completed',
      content: response.content,
      providerSessionId: response.providerSessionId
    };
  }
}

class OpenAIModelGateway implements ModelGateway {
  public async run(
    request: NativeAgentRunRequest,
    signal: AbortSignal
  ): Promise<NativeAgentRunResponse> {
    if (config.modelGateway.type !== 'openai') {
      throw new Error('OpenAI gateway is not configured.');
    }

    const response = await fetch(
      new URL('/v1/responses', config.modelGateway.baseUrl),
      {
        method: 'POST',
        headers: {
          authorization: `Bearer ${config.modelGateway.apiKey}`,
          'content-type': 'application/json'
        },
        body: JSON.stringify(openAIRequestBody(request, buildInput(request))),
        signal
      }
    );
    const body = (await response.json()) as OpenAIResponseBody;

    if (!response.ok) {
      throw new Error(
        openAIErrorMessage(body) ??
          `OpenAI gateway request failed with ${response.status}.`
      );
    }

    const timelineEvents: NativeAgentTimelineEventDraft[] = [
      {
        kind: 'status',
        title: 'Model response completed',
        detail: config.modelGateway.model,
        metadata: {
          provider: 'openai',
          responseId: typeof body.id === 'string' ? body.id : null
        }
      }
    ];

    return {
      content: extractOpenAIText(body),
      providerSessionId: typeof body.id === 'string' ? body.id : undefined,
      timelineEvents
    };
  }

  public async *runStream(
    request: NativeAgentRunRequest,
    signal: AbortSignal,
    runtime?: ModelGatewayRuntime
  ): AsyncIterable<NativeAgentStreamEvent> {
    if (config.modelGateway.type !== 'openai') {
      throw new Error('OpenAI gateway is not configured.');
    }

    if ((request.localTools?.length ?? 0) > 0 && runtime) {
      yield* this.runStreamWithLocalTools(request, signal, runtime);
      return;
    }

    const response = await fetch(
      new URL('/v1/responses', config.modelGateway.baseUrl),
      {
        method: 'POST',
        headers: {
          authorization: `Bearer ${config.modelGateway.apiKey}`,
          'content-type': 'application/json'
        },
        body: JSON.stringify(
          openAIRequestBody(request, buildInput(request), { stream: true })
        ),
        signal
      }
    );

    if (!response.ok) {
      const body = (await response.json()) as OpenAIResponseBody;
      throw new Error(
        openAIErrorMessage(body) ??
          `OpenAI gateway stream failed with ${response.status}.`
      );
    }

    yield* this.mapOpenAIStream(response, config.modelGateway.model);
  }

  private async *runStreamWithLocalTools(
    request: NativeAgentRunRequest,
    signal: AbortSignal,
    runtime: ModelGatewayRuntime
  ): AsyncIterable<NativeAgentStreamEvent> {
    if (config.modelGateway.type !== 'openai') {
      throw new Error('OpenAI gateway is not configured.');
    }

    const firstResponse = await fetch(
      new URL('/v1/responses', config.modelGateway.baseUrl),
      {
        method: 'POST',
        headers: {
          authorization: `Bearer ${config.modelGateway.apiKey}`,
          'content-type': 'application/json'
        },
        body: JSON.stringify(
          openAIRequestBody(request, buildInput(request), {
            includeTools: true
          })
        ),
        signal
      }
    );
    const firstBody = (await firstResponse.json()) as OpenAIResponseBody;

    if (!firstResponse.ok) {
      throw new Error(
        openAIErrorMessage(firstBody) ??
          `OpenAI gateway request failed with ${firstResponse.status}.`
      );
    }

    let currentBody = firstBody;
    let currentResponseId =
      typeof currentBody.id === 'string' ? currentBody.id : null;
    const maxToolRounds = 24;

    for (let round = 0; round < maxToolRounds; round += 1) {
      const toolCalls = localToolCallsFromOutput(currentBody, request);

      if (toolCalls.length === 0) {
        const content = extractOpenAIText(currentBody);
        assertNoRawToolCallText(content);

        for (const delta of textDeltas(content)) {
          yield { type: 'assistant_delta', delta };
        }

        yield {
          type: 'completed',
          content,
          providerSessionId: currentResponseId ?? undefined
        };
        return;
      }

      if (!currentResponseId) {
        throw new Error(
          'OpenAI gateway returned tool calls without a response id.'
        );
      }

      const toolOutputs = [];

      for (const call of toolCalls) {
        yield { type: 'local_tool_call', call };
        const result = await runtime.waitForLocalToolResult(call.id);
        yield { type: 'local_tool_result', result };

        toolOutputs.push({
          type: 'function_call_output',
          call_id: call.id,
          output: result.images?.length
            ? [
                { type: 'input_text', text: result.content },
                ...result.images.map((image) => ({
                  type: 'input_image',
                  image_url: `data:${image.mimeType};base64,${image.data}`,
                  detail: 'original'
                }))
              ]
            : result.content
        });
      }

      const nextResponse = await fetch(
        new URL('/v1/responses', config.modelGateway.baseUrl),
        {
          method: 'POST',
          headers: {
            authorization: `Bearer ${config.modelGateway.apiKey}`,
            'content-type': 'application/json'
          },
          body: JSON.stringify(
            openAIRequestBody(request, toolOutputs, {
              previousResponseId: currentResponseId,
              includeTools: true
            })
          ),
          signal
        }
      );
      const nextBody = (await nextResponse.json()) as OpenAIResponseBody;

      if (!nextResponse.ok) {
        throw new Error(
          openAIErrorMessage(nextBody) ??
            `OpenAI gateway request failed with ${nextResponse.status}.`
        );
      }

      currentBody = nextBody;
      currentResponseId =
        typeof currentBody.id === 'string' ? currentBody.id : currentResponseId;
    }

    if (!currentResponseId) {
      throw new Error('OpenAI gateway exceeded the local tool round limit.');
    }

    yield {
      type: 'timeline',
      event: {
        kind: 'status',
        title: 'Local tool round limit reached',
        detail: `Asking ${config.modelGateway.model} for a final answer without tools.`,
        metadata: {
          provider: 'openai',
          responseId: currentResponseId,
          maxToolRounds
        }
      }
    };

    const finalResponse = await fetch(
      new URL('/v1/responses', config.modelGateway.baseUrl),
      {
        method: 'POST',
        headers: {
          authorization: `Bearer ${config.modelGateway.apiKey}`,
          'content-type': 'application/json'
        },
        body: JSON.stringify(
          openAIRequestBody(
            request,
            [
              'Dony reached the local tool round limit. Stop calling tools now.',
              'Use the completed local tool results in the conversation to give the user a brief final status.',
              'If the task appears complete, say so. If it is not complete, say what remains.'
            ].join('\n'),
            {
              previousResponseId: currentResponseId
            }
          )
        ),
        signal
      }
    );
    const finalBody = (await finalResponse.json()) as OpenAIResponseBody;

    if (!finalResponse.ok) {
      throw new Error(
        openAIErrorMessage(finalBody) ??
          `OpenAI gateway request failed with ${finalResponse.status}.`
      );
    }

    const content = extractOpenAIText(finalBody);
    assertNoRawToolCallText(content);

    for (const delta of textDeltas(content)) {
      yield { type: 'assistant_delta', delta };
    }

    yield {
      type: 'completed',
      content,
      providerSessionId:
        typeof finalBody.id === 'string' ? finalBody.id : currentResponseId
    };
  }

  private async *mapOpenAIStream(
    response: Response,
    model: string
  ): AsyncIterable<NativeAgentStreamEvent> {
    let content = '';
    let responseId: string | undefined;

    for await (const event of openAIStreamEvents(response)) {
      switch (event.type) {
        case 'response.created': {
          const responseRecord = asRecord(event.response);
          responseId =
            typeof responseRecord?.id === 'string'
              ? responseRecord.id
              : responseId;
          yield {
            type: 'timeline',
            event: {
              kind: 'status',
              title: 'Model response started',
              detail: model,
              metadata: {
                provider: 'openai',
                responseId: responseId ?? null
              }
            }
          };
          break;
        }
        case 'response.output_text.delta':
          if (typeof event.delta === 'string' && event.delta.length > 0) {
            content += event.delta;
            yield { type: 'assistant_delta', delta: event.delta };
          }
          break;
        case 'response.completed': {
          const responseRecord = asRecord(event.response);
          responseId =
            typeof responseRecord?.id === 'string'
              ? responseRecord.id
              : responseId;
          yield {
            type: 'timeline',
            event: {
              kind: 'status',
              title: 'Model response completed',
              detail: model,
              metadata: {
                provider: 'openai',
                responseId: responseId ?? null
              }
            }
          };
          yield {
            type: 'completed',
            content,
            providerSessionId: responseId
          };
          break;
        }
        case 'error':
        case 'response.failed': {
          const error = asRecord(event.error);
          const message =
            typeof error?.message === 'string' &&
            error.message.trim().length > 0
              ? error.message.trim()
              : 'OpenAI gateway stream failed.';
          yield { type: 'error', message };
          break;
        }
        default:
          break;
      }
    }
  }
}

export const modelGateway: ModelGateway = (() => {
  switch (config.modelGateway.type) {
    case 'dev':
      return new DevModelGateway();
    case 'openai':
      return new OpenAIModelGateway();
    default:
      return assertNever(config.modelGateway);
  }
})();
