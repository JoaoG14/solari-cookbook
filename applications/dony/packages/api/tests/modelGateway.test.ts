import { afterEach, describe, expect, it, vi } from 'vitest';

import type { NativeAgentRunRequest } from '@dony/domain';

const baseRequest: NativeAgentRunRequest = {
  threadId: '11111111-1111-4111-8111-111111111111',
  agent: {
    id: '22222222-2222-4222-8222-222222222222',
    name: 'Operator',
    instructions: 'Be direct.',
    cwd: '/tmp/dony'
  },
  message: 'Plan my day',
  transcript: [
    {
      role: 'user',
      content: 'Earlier message'
    },
    {
      role: 'assistant',
      content: 'Earlier reply'
    }
  ],
  model: 'dony-auto',
  modelEffort: null
};

const stubBaseEnv = (): void => {
  vi.stubEnv('DATABASE_URL', 'postgres://dony:dony@127.0.0.1:5432/dony');
  vi.stubEnv('DONY_API_DEV_AUTH_TOKEN', 'dev-token');
};

const importGateway = async () => {
  vi.resetModules();
  return import('../src/modelGateway');
};

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe('modelGateway', () => {
  it('uses the development gateway by default', async () => {
    stubBaseEnv();
    const { modelGateway } = await importGateway();

    const response = await modelGateway.run(
      baseRequest,
      new AbortController().signal
    );

    expect(response.content).toContain('Dony received your task for Operator.');
    expect(response.timelineEvents).toEqual([
      expect.objectContaining({
        kind: 'status',
        title: 'Dony backend reached'
      })
    ]);
  });

  it('maps OpenAI responses into native agent responses', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');

    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          id: 'resp_123',
          output: [
            {
              type: 'message',
              content: [
                {
                  type: 'output_text',
                  text: 'Model answer.'
                }
              ]
            }
          ]
        }),
        { status: 200 }
      )
    );
    vi.stubGlobal('fetch', fetchMock);

    const { modelGateway } = await importGateway();
    const response = await modelGateway.run(
      { ...baseRequest, modelServiceTier: 'priority' },
      new AbortController().signal
    );

    expect(fetchMock).toHaveBeenCalledWith(
      new URL('/v1/responses', 'https://api.openai.com'),
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          authorization: 'Bearer openai-key'
        })
      })
    );
    const requestBody = JSON.parse(
      fetchMock.mock.calls[0]?.[1]?.body as string
    );
    expect(requestBody).toEqual(
      expect.objectContaining({
        model: 'gpt-test',
        service_tier: 'priority',
        instructions: expect.stringContaining('Agent name: Operator'),
        input: expect.stringContaining('USER: Plan my day')
      })
    );
    expect(requestBody.instructions).not.toContain('Agent role:');
    expect(response).toEqual({
      content: 'Model answer.',
      providerSessionId: 'resp_123',
      timelineEvents: [
        expect.objectContaining({
          kind: 'status',
          title: 'Model response completed',
          detail: 'gpt-test'
        })
      ]
    });
  });

  it('applies a fixed agent response language to the model prompt', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          id: 'resp_language',
          output: [
            {
              type: 'message',
              content: [{ type: 'output_text', text: 'Feito.' }]
            }
          ]
        }),
        { status: 200 }
      )
    );
    vi.stubGlobal('fetch', fetchMock);
    const { modelGateway } = await importGateway();

    await modelGateway.run(
      { ...baseRequest, agentResponseLanguage: 'pt-BR' },
      new AbortController().signal
    );

    const requestBody = JSON.parse(
      fetchMock.mock.calls[0]?.[1]?.body as string
    );
    expect(requestBody.instructions).toContain(
      'Write the response in Brazilian Portuguese'
    );
    expect(requestBody.instructions).not.toContain(
      'Match the language of the latest user request'
    );
  });

  it('maps screenshots to OpenAI vision input', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');

    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ output_text: '{"tasks":["Call Ana"]}' }), {
        status: 200
      })
    );
    vi.stubGlobal('fetch', fetchMock);

    const { modelGateway } = await importGateway();

    await modelGateway.run(
      {
        ...baseRequest,
        images: [
          {
            name: 'todos.png',
            mimeType: 'image/png',
            base64: 'aW1hZ2U='
          }
        ]
      },
      new AbortController().signal
    );

    const body = JSON.parse(
      fetchMock.mock.calls[0]?.[1]?.body as string
    ) as Record<string, unknown>;

    expect(body.input).toEqual([
      {
        role: 'user',
        content: [
          {
            type: 'input_text',
            text: expect.stringContaining('USER: Plan my day')
          },
          {
            type: 'input_image',
            image_url: 'data:image/png;base64,aW1hZ2U=',
            detail: 'high'
          }
        ]
      }
    ]);
  });

  it('requests structured OpenAI output when the app supplies a schema', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ output_text: '{"tasks":[]}' }), {
        status: 200
      })
    );
    vi.stubGlobal('fetch', fetchMock);
    const outputSchema = {
      type: 'object',
      properties: { tasks: { type: 'array', items: { type: 'string' } } },
      required: ['tasks'],
      additionalProperties: false
    };
    const { modelGateway } = await importGateway();

    await modelGateway.run(
      { ...baseRequest, outputSchema },
      new AbortController().signal
    );

    expect(JSON.parse(fetchMock.mock.calls[0]?.[1]?.body as string)).toEqual(
      expect.objectContaining({
        text: {
          format: {
            type: 'json_schema',
            name: 'dony_app_ai',
            schema: outputSchema,
            strict: true
          }
        }
      })
    );
  });

  it('streams development gateway events', async () => {
    stubBaseEnv();
    const { modelGateway } = await importGateway();

    const events = [];

    for await (const event of modelGateway.runStream(
      baseRequest,
      new AbortController().signal
    )) {
      events.push(event);
    }

    expect(events[0]).toEqual(expect.objectContaining({ type: 'timeline' }));
    expect(events).toContainEqual(
      expect.objectContaining({ type: 'assistant_delta' })
    );
    expect(events.at(-1)).toEqual(
      expect.objectContaining({ type: 'completed' })
    );
  });

  it('bridges development local tool calls through the runtime', async () => {
    stubBaseEnv();
    const { modelGateway } = await importGateway();
    const waitForLocalToolResult = vi.fn().mockResolvedValue({
      callId: 'ignored',
      status: 'success',
      content: '{"entries":[]}'
    });
    const events = [];

    for await (const event of modelGateway.runStream(
      {
        ...baseRequest,
        runId: '33333333-3333-4333-8333-333333333333',
        message: 'Organize Downloads folder',
        localTools: ['filesystem_list_directory']
      },
      new AbortController().signal,
      { waitForLocalToolResult }
    )) {
      events.push(event);
    }

    expect(events).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: 'local_tool_call',
          call: expect.objectContaining({
            name: 'filesystem_list_directory',
            arguments: { path: '~/Downloads' }
          })
        }),
        expect.objectContaining({ type: 'local_tool_result' })
      ])
    );
    expect(waitForLocalToolResult).toHaveBeenCalledWith(expect.any(String));
  });

  it('routes a Desktop request to ~/Desktop without asking the user', async () => {
    stubBaseEnv();
    const { modelGateway } = await importGateway();
    const waitForLocalToolResult = vi.fn().mockResolvedValue({
      callId: 'ignored',
      status: 'success',
      content: '{"entries":[]}'
    });
    const events = [];

    for await (const event of modelGateway.runStream(
      {
        ...baseRequest,
        runId: '33333333-3333-4333-8333-333333333333',
        message: 'Organize the files at my desktop',
        localTools: ['filesystem_list_directory', 'ask_user']
      },
      new AbortController().signal,
      { waitForLocalToolResult }
    )) {
      events.push(event);
    }

    const localToolCalls = events.filter(
      (event) => event.type === 'local_tool_call'
    );

    expect(localToolCalls).toEqual([
      expect.objectContaining({
        call: expect.objectContaining({
          name: 'filesystem_list_directory',
          arguments: { path: '~/Desktop' }
        })
      })
    ]);
  });

  it('does not default generic filesystem requests to the working directory', async () => {
    stubBaseEnv();
    const { modelGateway } = await importGateway();
    const waitForLocalToolResult = vi.fn();

    for await (const _event of modelGateway.runStream(
      {
        ...baseRequest,
        runId: '33333333-3333-4333-8333-333333333333',
        message: 'Organize my files',
        localTools: ['filesystem_list_directory']
      },
      new AbortController().signal,
      { waitForLocalToolResult }
    )) {
      // Exhaust the stream so the development response completes.
    }

    expect(waitForLocalToolResult).not.toHaveBeenCalled();
  });

  it('maps OpenAI SSE chunks into native stream events', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');

    const stream = new ReadableStream({
      start(controller) {
        controller.enqueue(
          new TextEncoder().encode(
            [
              `data: ${JSON.stringify({
                type: 'response.created',
                response: { id: 'resp_stream' }
              })}`,
              '',
              `data: ${JSON.stringify({
                type: 'response.output_text.delta',
                delta: 'Hello'
              })}`,
              '',
              `data: ${JSON.stringify({
                type: 'response.output_text.delta',
                delta: ' world'
              })}`,
              '',
              `data: ${JSON.stringify({
                type: 'response.completed',
                response: { id: 'resp_stream' }
              })}`,
              ''
            ].join('\n')
          )
        );
        controller.close();
      }
    });
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(new Response(stream, { status: 200 }))
    );

    const { modelGateway } = await importGateway();
    const events = [];

    for await (const event of modelGateway.runStream(
      baseRequest,
      new AbortController().signal
    )) {
      events.push(event);
    }

    expect(events).toEqual([
      expect.objectContaining({
        type: 'timeline',
        event: expect.objectContaining({ title: 'Model response started' })
      }),
      { type: 'assistant_delta', delta: 'Hello' },
      { type: 'assistant_delta', delta: ' world' },
      expect.objectContaining({
        type: 'timeline',
        event: expect.objectContaining({ title: 'Model response completed' })
      }),
      {
        type: 'completed',
        content: 'Hello world',
        providerSessionId: 'resp_stream'
      }
    ]);
  });

  it('bridges OpenAI function calls through local tool results', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');

    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            id: 'resp_tool',
            output: [
              {
                type: 'function_call',
                call_id: 'call_1',
                name: 'filesystem_list_directory',
                arguments: JSON.stringify({ path: '.' })
              }
            ]
          }),
          { status: 200 }
        )
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            id: 'resp_final',
            output: [
              {
                type: 'message',
                content: [
                  {
                    type: 'output_text',
                    text: 'Final answer'
                  }
                ]
              }
            ]
          }),
          { status: 200 }
        )
      );
    vi.stubGlobal('fetch', fetchMock);

    const { modelGateway } = await importGateway();
    const events = [];

    for await (const event of modelGateway.runStream(
      {
        ...baseRequest,
        runId: '33333333-3333-4333-8333-333333333333',
        localTools: ['filesystem_list_directory']
      },
      new AbortController().signal,
      {
        waitForLocalToolResult: vi.fn().mockResolvedValue({
          callId: 'call_1',
          status: 'success',
          content: '{"entries":[]}'
        })
      }
    )) {
      events.push(event);
    }

    expect(events).toEqual([
      expect.objectContaining({
        type: 'local_tool_call',
        call: expect.objectContaining({ id: 'call_1' })
      }),
      expect.objectContaining({ type: 'local_tool_result' }),
      { type: 'assistant_delta', delta: 'Final answer' },
      {
        type: 'completed',
        content: 'Final answer',
        providerSessionId: 'resp_final'
      }
    ]);
    expect(JSON.parse(fetchMock.mock.calls[1]?.[1]?.body as string)).toEqual(
      expect.objectContaining({
        previous_response_id: 'resp_tool',
        tools: expect.any(Array),
        input: [
          {
            type: 'function_call_output',
            call_id: 'call_1',
            output: '{"entries":[]}'
          }
        ]
      })
    );

    const initialRequest = JSON.parse(
      fetchMock.mock.calls[0]?.[1]?.body as string
    );
    const filesystemTool = initialRequest.tools.find(
      (tool: { name?: string }) => tool.name === 'filesystem_list_directory'
    );

    expect(initialRequest.instructions).toContain('Autonomy policy');
    expect(initialRequest.instructions).toContain('Response style:');
    expect(initialRequest.instructions).toContain(
      'Match the language of the latest user request. Use another language only when the user explicitly asks for it.'
    );
    expect(initialRequest.instructions).toContain('Never use em dashes');
    expect(initialRequest.instructions).toContain(
      'Default to one to three short sentences or at most three bullets.'
    );
    expect(initialRequest.instructions).toContain(
      'Do not restate the request, narrate routine work, or add unsolicited explanation.'
    );
    expect(initialRequest.instructions).toContain(
      "Act directly when the user's goal is clear"
    );
    expect(initialRequest.instructions).toContain(
      "Do not ask for confirmation for steps directly implied by the user's request"
    );
    expect(filesystemTool.description).toContain("user's local filesystem");
    expect(filesystemTool.description).toContain('~/Desktop');
  });

  it('includes the CUA operating policy when computer tools are available', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');

    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          id: 'resp_final',
          output: [
            {
              type: 'message',
              content: [
                {
                  type: 'output_text',
                  text: 'Done.'
                }
              ]
            }
          ]
        }),
        { status: 200 }
      )
    );
    vi.stubGlobal('fetch', fetchMock);

    const { modelGateway } = await importGateway();

    for await (const _event of modelGateway.runStream(
      {
        ...baseRequest,
        runId: '33333333-3333-4333-8333-333333333333',
        localTools: ['computer_use']
      },
      new AbortController().signal,
      {
        waitForLocalToolResult: vi.fn()
      }
    )) {
      // Exhaust the stream so the request is sent.
    }

    const requestBody = JSON.parse(
      fetchMock.mock.calls[0]?.[1]?.body as string
    );
    const computerTool = requestBody.tools.find(
      (tool: { name?: string }) => tool.name === 'computer_use'
    );

    expect(requestBody.instructions).toContain('Computer-use policy');
    expect(requestBody.instructions).toContain('Inspect before acting');
    expect(requestBody.instructions).toContain('Reuse existing windows/tabs');
    expect(computerTool.description).toContain('existing-window-first');
    expect(computerTool.parameters.properties.action.description).toContain(
      'Use launch_app only when no suitable existing window/app is available'
    );
    expect(
      computerTool.parameters.properties.element_index.description
    ).toContain('Requires its matching snapshot_id');
    expect(computerTool.parameters.properties.element_token).toBeDefined();
    expect(computerTool.parameters.properties.delivery_mode.enum).toEqual([
      'background',
      'foreground',
      null
    ]);
  });

  it('applies the selected design to native task output instructions', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          id: 'resp_final',
          output: [
            {
              type: 'message',
              content: [{ type: 'output_text', text: 'Done.' }]
            }
          ]
        }),
        { status: 200 }
      )
    );
    vi.stubGlobal('fetch', fetchMock);
    const { modelGateway } = await importGateway();

    await modelGateway.run(
      {
        ...baseRequest,
        localTools: ['publish_task_output'],
        taskOutputDesign: 'editorial-cards'
      },
      new AbortController().signal
    );

    const requestBody = JSON.parse(
      fetchMock.mock.calls[0]?.[1]?.body as string
    );
    expect(requestBody.instructions).toContain('publish_task_output');
    expect(requestBody.instructions).toContain(
      '#f5f3f1 warm-gray content cards'
    );
    expect(requestBody.instructions).toContain(
      'keep the chat response to one short sentence saying it is ready'
    );
  });

  it('includes ask_user for blocking clarification and confirmation', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');

    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          id: 'resp_final',
          output: [
            {
              type: 'message',
              content: [
                {
                  type: 'output_text',
                  text: 'Done.'
                }
              ]
            }
          ]
        }),
        { status: 200 }
      )
    );
    vi.stubGlobal('fetch', fetchMock);

    const { modelGateway } = await importGateway();

    for await (const _event of modelGateway.runStream(
      {
        ...baseRequest,
        runId: '33333333-3333-4333-8333-333333333333',
        localTools: ['ask_user']
      },
      new AbortController().signal,
      {
        waitForLocalToolResult: vi.fn()
      }
    )) {
      // Exhaust the stream so the request is sent.
    }

    const requestBody = JSON.parse(
      fetchMock.mock.calls[0]?.[1]?.body as string
    );
    const askUserTool = requestBody.tools.find(
      (tool: { name?: string }) => tool.name === 'ask_user'
    );

    expect(requestBody.instructions).toContain(
      'Ask only when a missing decision would significantly change the intended outcome'
    );
    expect(requestBody.instructions).toContain(
      'When ask_user is needed, use it instead of ending the run with a question in assistant text'
    );
    expect(requestBody.instructions).toContain(
      'set responseKind to resource and do not offer placeholder choices'
    );
    expect(requestBody.instructions).toContain(
      'use ask_user for missing details before attempting the connector action'
    );
    expect(requestBody.instructions).toContain(
      'Use connector_use search_tools before execute_tool'
    );
    expect(askUserTool.description).toContain(
      'Do not ask about conventional low-risk details'
    );
    expect(askUserTool.parameters.required).toEqual([
      'header',
      'question',
      'optionsJson',
      'allowCustomAnswer',
      'multiple',
      'responseKind'
    ]);
  });

  it('continues OpenAI local tool rounds until the model returns text', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');

    const toolResponses = Array.from(
      { length: 10 },
      (_, index) =>
        new Response(
          JSON.stringify({
            id: `resp_tool_${index + 1}`,
            output: [
              {
                type: 'function_call',
                call_id: `call_${index + 1}`,
                name: 'computer_use',
                arguments: JSON.stringify({
                  action: index === 0 ? 'open' : 'screenshot',
                  target: index === 0 ? 'https://music.youtube.com' : null,
                  x: null,
                  y: null,
                  text: null,
                  key: null,
                  keys: null,
                  app: null,
                  args: null
                })
              }
            ]
          }),
          { status: 200 }
        )
    );
    const fetchMock = vi.fn();

    for (const response of toolResponses) {
      fetchMock.mockResolvedValueOnce(response);
    }

    fetchMock.mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          id: 'resp_done',
          output: [
            {
              type: 'message',
              content: [
                {
                  type: 'output_text',
                  text: 'Music is playing.'
                }
              ]
            }
          ]
        }),
        { status: 200 }
      )
    );
    vi.stubGlobal('fetch', fetchMock);

    const waitForLocalToolResult = vi.fn(async (callId: string) => ({
      callId,
      status: 'success',
      content: '{"success":true}'
    }));
    const { modelGateway } = await importGateway();
    const events = [];

    for await (const event of modelGateway.runStream(
      {
        ...baseRequest,
        runId: '33333333-3333-4333-8333-333333333333',
        localTools: ['computer_use']
      },
      new AbortController().signal,
      { waitForLocalToolResult }
    )) {
      events.push(event);
    }

    expect(
      events.filter((event) => event.type === 'local_tool_call')
    ).toHaveLength(10);
    expect(waitForLocalToolResult).toHaveBeenCalledTimes(10);
    expect(events.at(-1)).toEqual({
      type: 'completed',
      content: 'Music is playing.',
      providerSessionId: 'resp_done'
    });
    expect(fetchMock).toHaveBeenCalledTimes(11);
  });

  it('sends computer screenshots back to OpenAI as image input', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            id: 'resp_capture',
            output: [
              {
                type: 'function_call',
                call_id: 'capture-1',
                name: 'computer_use',
                arguments: JSON.stringify({
                  action: 'get_window_state',
                  pid: 90,
                  window_id: 42
                })
              }
            ]
          }),
          { status: 200 }
        )
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            id: 'resp_done',
            output: [
              {
                type: 'message',
                content: [
                  { type: 'output_text', text: 'I can see the window.' }
                ]
              }
            ]
          }),
          { status: 200 }
        )
      );
    vi.stubGlobal('fetch', fetchMock);
    const { modelGateway } = await importGateway();
    for await (const _event of modelGateway.runStream(
      {
        ...baseRequest,
        localTools: ['computer_use']
      },
      new AbortController().signal,
      {
        waitForLocalToolResult: vi.fn(async (callId: string) => ({
          callId,
          status: 'success',
          content: '{"snapshot_id":"s12345678"}',
          images: [{ data: 'cG5n', mimeType: 'image/png' }]
        }))
      }
    )) {
      /* Exhaust the two-turn tool loop. */
    }
    const followup = JSON.parse(fetchMock.mock.calls[1]![1].body as string);
    expect(followup.input).toEqual([
      {
        type: 'function_call_output',
        call_id: 'capture-1',
        output: [
          { type: 'input_text', text: '{"snapshot_id":"s12345678"}' },
          {
            type: 'input_image',
            image_url: 'data:image/png;base64,cG5n',
            detail: 'original'
          }
        ]
      }
    ]);
  });

  it('bridges connector_use through local tool results', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');

    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            id: 'resp_connector',
            output: [
              {
                type: 'function_call',
                call_id: 'call_connector',
                name: 'connector_use',
                arguments: JSON.stringify({
                  action: 'execute_tool',
                  toolkit: 'googledrive',
                  query: null,
                  toolSlug: 'GOOGLEDRIVE_UPLOAD_FILE',
                  argumentsJson: JSON.stringify({ folder_id: 'folder-1' }),
                  localFiles: [
                    {
                      argumentName: 'file_to_upload',
                      path: '/tmp/report.pptx',
                      mimeType:
                        'application/vnd.openxmlformats-officedocument.presentationml.presentation'
                    }
                  ]
                })
              }
            ]
          }),
          { status: 200 }
        )
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            id: 'resp_done',
            output: [
              {
                type: 'message',
                content: [
                  {
                    type: 'output_text',
                    text: 'I found the email.'
                  }
                ]
              }
            ]
          }),
          { status: 200 }
        )
      );
    vi.stubGlobal('fetch', fetchMock);

    const waitForLocalToolResult = vi.fn(async (callId: string) => ({
      callId,
      status: 'success',
      content: JSON.stringify({ emails: [{ subject: 'Hello' }] })
    }));
    const { modelGateway } = await importGateway();
    const events = [];

    for await (const event of modelGateway.runStream(
      {
        ...baseRequest,
        runId: '33333333-3333-4333-8333-333333333333',
        localTools: ['connector_use']
      },
      new AbortController().signal,
      { waitForLocalToolResult }
    )) {
      events.push(event);
    }

    expect(waitForLocalToolResult).toHaveBeenCalledWith('call_connector');
    expect(events).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: 'local_tool_call',
          call: expect.objectContaining({
            id: 'call_connector',
            name: 'connector_use',
            arguments: expect.objectContaining({
              localFiles: [
                expect.objectContaining({
                  argumentName: 'file_to_upload',
                  path: '/tmp/report.pptx'
                })
              ]
            })
          })
        }),
        expect.objectContaining({
          type: 'local_tool_result',
          result: expect.objectContaining({ callId: 'call_connector' })
        })
      ])
    );
    expect(events.at(-1)).toEqual({
      type: 'completed',
      content: 'I found the email.',
      providerSessionId: 'resp_done'
    });
  });

  it('asks OpenAI for a final answer instead of failing after the local tool round limit', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');

    const toolResponses = Array.from(
      { length: 25 },
      (_, index) =>
        new Response(
          JSON.stringify({
            id: `resp_tool_${index + 1}`,
            output: [
              {
                type: 'function_call',
                call_id: `call_${index + 1}`,
                name: 'computer_use',
                arguments: JSON.stringify({
                  action: 'screenshot',
                  target: null,
                  x: null,
                  y: null,
                  text: null,
                  key: null,
                  keys: null,
                  app: null,
                  args: null
                })
              }
            ]
          }),
          { status: 200 }
        )
    );
    const fetchMock = vi.fn();

    for (const response of toolResponses) {
      fetchMock.mockResolvedValueOnce(response);
    }

    fetchMock.mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          id: 'resp_final_after_limit',
          output: [
            {
              type: 'message',
              content: [
                {
                  type: 'output_text',
                  text: 'The music is playing.'
                }
              ]
            }
          ]
        }),
        { status: 200 }
      )
    );
    vi.stubGlobal('fetch', fetchMock);

    const waitForLocalToolResult = vi.fn(async (callId: string) => ({
      callId,
      status: 'success',
      content: '{"success":true}'
    }));
    const { modelGateway } = await importGateway();
    const events = [];

    for await (const event of modelGateway.runStream(
      {
        ...baseRequest,
        runId: '33333333-3333-4333-8333-333333333333',
        localTools: ['computer_use']
      },
      new AbortController().signal,
      { waitForLocalToolResult }
    )) {
      events.push(event);
    }

    expect(
      events.filter((event) => event.type === 'local_tool_call')
    ).toHaveLength(24);
    expect(events).toContainEqual({
      type: 'timeline',
      event: {
        kind: 'status',
        title: 'Local tool round limit reached',
        detail: 'Asking gpt-test for a final answer without tools.',
        metadata: {
          provider: 'openai',
          responseId: 'resp_tool_25',
          maxToolRounds: 24
        }
      }
    });
    expect(waitForLocalToolResult).toHaveBeenCalledTimes(24);
    expect(events.at(-1)).toEqual({
      type: 'completed',
      content: 'The music is playing.',
      providerSessionId: 'resp_final_after_limit'
    });

    const finalRequest = JSON.parse(
      fetchMock.mock.calls.at(-1)?.[1]?.body as string
    );
    expect(finalRequest).toEqual(
      expect.objectContaining({
        previous_response_id: 'resp_tool_25',
        input: expect.stringContaining('Stop calling tools now.')
      })
    );
    expect(finalRequest.tools).toBeUndefined();
  });

  it('rejects raw tool-call text from OpenAI when local tools are available', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');

    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            id: 'resp_raw_tool',
            output: [
              {
                type: 'message',
                content: [
                  {
                    type: 'output_text',
                    text: [
                      'I will use the desktop.',
                      '<tool_call>{"name":"functions.computer_use","arguments":{"action":"get_screenshot"}}</tool_call>'
                    ].join('\n')
                  }
                ]
              }
            ]
          }),
          { status: 200 }
        )
      )
    );

    const { modelGateway } = await importGateway();
    const events = [];

    await expect(async () => {
      for await (const event of modelGateway.runStream(
        {
          ...baseRequest,
          runId: '33333333-3333-4333-8333-333333333333',
          localTools: ['computer_use']
        },
        new AbortController().signal,
        {
          waitForLocalToolResult: vi.fn()
        }
      )) {
        events.push(event);
      }
    }).rejects.toThrow('raw tool-call text');
    expect(events).toEqual([]);
  });

  it('rejects chat-template tool-call text from OpenAI when local tools are available', async () => {
    stubBaseEnv();
    vi.stubEnv('DONY_MODEL_GATEWAY', 'openai');
    vi.stubEnv('DONY_OPENAI_API_KEY', 'openai-key');
    vi.stubEnv('DONY_OPENAI_MODEL', 'gpt-test');

    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            id: 'resp_chat_template_tool',
            output: [
              {
                type: 'message',
                content: [
                  {
                    type: 'output_text',
                    text: [
                      'Checking the desktop.',
                      '<|assistant to=functions.computer_use |>{"action":"get_screenshot","x":null,"y":null,"text":null,"key":null,"keys":null,"target":null,"app":null,"args":null}<|tool_call|>'
                    ].join('\n')
                  }
                ]
              }
            ]
          }),
          { status: 200 }
        )
      )
    );

    const { modelGateway } = await importGateway();

    await expect(async () => {
      for await (const _event of modelGateway.runStream(
        {
          ...baseRequest,
          runId: '33333333-3333-4333-8333-333333333333',
          localTools: ['computer_use']
        },
        new AbortController().signal,
        {
          waitForLocalToolResult: vi.fn()
        }
      )) {
        // The raw tool-call text should fail before any stream event is emitted.
      }
    }).rejects.toThrow('raw tool-call text');
  });
});
