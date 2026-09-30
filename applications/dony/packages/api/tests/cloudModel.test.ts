import { afterEach, expect, it, vi } from 'vitest';
import { tool, type ToolSet } from 'ai';
import { z } from 'zod';
import { createCloudModel } from '../src/cloudModel';
import type { CloudJob, CloudStore } from '../src/cloudStore';
import { CloudError } from '../src/cloudCommands';

afterEach(() => vi.unstubAllGlobals());

it.each([
  ['quick', 'gpt-6-luna', 'low'],
  ['everyday', 'gpt-5.6-terra', 'low'],
  ['balanced', 'gpt-5.6-terra', 'medium'],
  ['thorough', 'gpt-6-sol', 'medium'],
  ['deep', 'gpt-6-astra', 'medium']
] as const)(
  'routes %s to %s at %s',
  async (thinking, modelId, effort) => {
    const requests: { provider: { max_price: { prompt: number } } }[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL | Request, options?: RequestInit) => {
        if (String(url).endsWith('/models'))
          return Response.json({
            data: ['gpt-6-luna', 'gpt-5.6-terra', 'gpt-6-sol', 'gpt-6-astra'].map((name, index) => ({
              id: `openai/${name}`,
              context_length: 100_000,
              pricing: {
                prompt: 0.000001 * (index + 1),
                completion: 0.000002 * (index + 1)
              },
              supported_parameters: ['tools', 'reasoning'],
              reasoning: {
                supported_efforts: ['low', 'medium', 'high']
              }
            }))
          });
        requests.push(JSON.parse(options!.body as string));
        return stream({ content: 'Done' });
      })
    );
    const store = {
      reserve: vi.fn(async () => 'reservation'),
      settle: vi.fn(async () => {}),
      recordGeneration: vi.fn(async () => {}),
      markUnknownCost: vi.fn(async () => {})
    };
    const model = createCloudModel(store as unknown as CloudStore, {
      apiKey: 'test-key',
      model: 'openai/gpt-5.6-terra'
    });
    await model.step({ id: 'test-job' } as CloudJob, {
      instructions: 'Help.',
      messages: [{ role: 'user', content: 'Hello' }],
      tools: {},
      signal: new AbortController().signal,
      thinking
    });
    expect(requests[0]).toMatchObject({
      model: `openai/${modelId}`,
      reasoning: { effort }
    });
    expect(requests[0]!.provider.max_price.prompt).toBe(
      ['gpt-6-luna', 'gpt-5.6-terra', 'gpt-6-sol', 'gpt-6-astra'].indexOf(modelId) + 1
    );
    expect(store.reserve).toHaveBeenCalledOnce();
    expect(store.settle).toHaveBeenCalledWith('reservation', 0.001);
  }
);

it.each([false, true])(
  'routes tool requests using advertised parallel-call support (%s)',
  async (supportsParallelCalls) => {
    let request: Record<string, unknown> | undefined;
    const parameters = ['tools', 'tool_choice', 'max_tokens'];
    if (supportsParallelCalls) parameters.push('parallel_tool_calls');
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL | Request, options?: RequestInit) => {
        if (String(url).endsWith('/models')) {
          return Response.json({
            data: [
              {
                id: 'openai/gpt-5.6-terra',
                context_length: 1_050_000,
                pricing: { prompt: '0.000002', completion: '0.000012' },
                supported_parameters: parameters
              }
            ]
          });
        }
        request = JSON.parse(options!.body as string);
        // Reproduce OpenRouter's strict routing rejection at the HTTP boundary.
        if (!supportsParallelCalls && 'parallel_tool_calls' in request!) {
          return Response.json(
            {
              error: {
                message:
                  'No endpoints found that can handle the requested parameters.',
                code: 404
              }
            },
            { status: 404 }
          );
        }
        const chunk = {
          id: 'generation-test',
          model: 'openai/gpt-5.6-terra',
          created: 1,
          choices: [
            { index: 0, delta: { content: '42' }, finish_reason: 'stop' }
          ],
          usage: {
            prompt_tokens: 10,
            completion_tokens: 1,
            total_tokens: 11,
            cost: 0.000032
          }
        };
        return new Response(
          `data: ${JSON.stringify(chunk)}\n\ndata: [DONE]\n\n`,
          {
            headers: { 'Content-Type': 'text/event-stream' }
          }
        );
      })
    );
    const store = {
      reserve: vi.fn(async () => 'reservation'),
      settle: vi.fn(async () => {}),
      recordGeneration: vi.fn(async () => {}),
      markUnknownCost: vi.fn(async () => {})
    };
    const model = createCloudModel(store as unknown as CloudStore, {
      apiKey: 'test-key',
      model: 'openai/gpt-5.6-terra'
    });
    const result = await model.step({ id: 'test-job' } as CloudJob, {
      instructions: 'Answer briefly.',
      messages: [{ role: 'user', content: '17 + 25?' }],
      tools: {
        add: tool({
          description: 'Add two numbers.',
          inputSchema: z.object({ a: z.number(), b: z.number() }),
          execute: async ({ a, b }) => a + b
        })
      },
      signal: new AbortController().signal
    });
    expect(result).toMatchObject({ text: '42', finished: true });
    if (supportsParallelCalls) expect(request!.parallel_tool_calls).toBe(false);
    else expect(request).not.toHaveProperty('parallel_tool_calls');
    expect(request!.tools).toHaveLength(1);
    expect(request!.provider).toEqual({
      require_parameters: true,
      max_price: { prompt: 2, completion: 12, request: 0 }
    });
    expect(store.settle).toHaveBeenCalledWith('reservation', 0.000032);
  }
);

function stream(delta: unknown, reason = 'stop', cost: number | null = 0.001) {
  return new Response(
    `data: ${JSON.stringify({
      id: 'gen-test',
      model: 'test-model',
      created: 1,
      choices: [{ index: 0, delta, finish_reason: reason }],
      usage: {
        prompt_tokens: 20,
        completion_tokens: 10,
        total_tokens: 30,
        ...(cost === null ? {} : { cost })
      }
    })}\n\ndata: [DONE]\n\n`,
    {
      headers: {
        'Content-Type': 'text/event-stream',
        'x-generation-id': 'gen-test'
      }
    }
  );
}

function fixture(
  reply: (request: Record<string, unknown>) => Response | Promise<Response>
) {
  const store = {
    reserve: vi.fn(async (_job: CloudJob, _dollars: number) => 'reservation'),
    settle: vi.fn(async (_id: string, _cost?: number, _status?: string) => {}),
    recordGeneration: vi.fn(async () => {}),
    markUnknownCost: vi.fn(async () => {}),
    costsToReconcile: vi.fn(async () => [
      { id: 'reservation', generation_id: 'gen-test' }
    ])
  };
  const fetchMock = vi.fn(
    async (url: string | URL | Request, options?: RequestInit) => {
      if (String(url).endsWith('/models'))
        return Response.json({
          data: [
            {
              id: 'test-model',
              context_length: 1_050_000,
              pricing: { prompt: '0.000002', completion: '0.000012' },
              supported_parameters: ['tools', 'max_tokens']
            }
          ]
        });
      return reply(options?.body ? JSON.parse(options.body as string) : {});
    }
  );
  vi.stubGlobal('fetch', fetchMock);
  const model = createCloudModel(store as unknown as CloudStore, {
    apiKey: 'test-key',
    model: 'test-model'
  });
  const input = {
    instructions: 'Help with this task.',
    messages: [{ role: 'user' as const, content: 'Research AI news.' }],
    tools: {} as ToolSet,
    signal: new AbortController().signal
  };
  return {
    model,
    store,
    input,
    fetchMock,
    job: { id: 'test-job' } as CloudJob
  };
}

it('reserves cents for short text, increases with content and tool schemas, and bounds opaque inputs', async () => {
  const { model, store, input, job } = fixture(() =>
    stream({ content: 'Done' })
  );
  await model.step(job, input);
  const short = store.reserve.mock.calls.at(-1)![1];
  expect(short).toBeLessThan(0.15);
  await model.step(job, {
    ...input,
    messages: [{ role: 'user', content: '日'.repeat(10_000) }]
  });
  expect(store.reserve.mock.calls.at(-1)![1]).toBeGreaterThan(short + 0.06);
  await model.step(job, {
    ...input,
    tools: {
      read: tool({
        description: 'Details '.repeat(10_000),
        inputSchema: z.object({ id: z.string() })
      })
    }
  });
  expect(store.reserve.mock.calls.at(-1)![1]).toBeGreaterThan(short + 0.1);
  await model.step(job, { ...input, search: true });
  expect(store.reserve.mock.calls.at(-1)![1]).toBeCloseTo(2.248304);
  await model.step(job, {
    ...input,
    messages: [
      {
        role: 'user',
        content: [{ type: 'image', image: new Uint8Array([1, 2, 3]) }]
      }
    ]
  });
  expect(store.reserve.mock.calls.at(-1)![1]).toBeCloseTo(2.198304);
});

it('settles the parent before reserving a nested search and preserves tool results', async () => {
  const events: string[] = [];
  const { model, store, input, job } = fixture((request) =>
    request.plugins
      ? stream({ content: 'Sources found' }, 'stop', 0.007)
      : stream(
          {
            tool_calls: [
              {
                index: 0,
                id: 'call-search',
                type: 'function',
                function: {
                  name: 'web_search',
                  arguments: '{"query":"AI news"}'
                }
              }
            ]
          },
          'tool_calls'
        )
  );
  store.reserve.mockImplementation(async () => {
    events.push('reserve');
    return `reservation-${events.length}`;
  });
  store.settle.mockImplementation(async () => {
    events.push('settle');
  });
  input.tools = {
    web_search: tool({
      inputSchema: z.object({ query: z.string() }),
      execute: async () => {
        events.push('search');
        return (await model.step(job, { ...input, tools: {}, search: true }))
          .text;
      }
    })
  };
  const result = await model.step(job, input);
  expect(events).toEqual(['reserve', 'settle', 'search', 'reserve', 'settle']);
  expect(result.finished).toBe(false);
  expect(result.messages.at(-1)).toMatchObject({
    role: 'tool',
    content: [
      {
        toolCallId: 'call-search',
        output: { type: 'json', value: 'Sources found' }
      }
    ]
  });
});

it('propagates a search budget failure instead of letting the agent explain it as success', async () => {
  const { model, store, input, job } = fixture(() =>
    stream(
      {
        tool_calls: [
          {
            index: 0,
            id: 'call-search',
            type: 'function',
            function: { name: 'web_search', arguments: '{}' }
          }
        ]
      },
      'tool_calls'
    )
  );
  const error = new CloudError(
    429,
    'Dony has reached today’s usage limit. Your task is still saved.'
  );
  input.tools = {
    web_search: tool({
      inputSchema: z.object({}),
      execute: async () => {
        throw error;
      }
    })
  };
  await expect(model.step(job, input)).rejects.toBe(error);
  expect(store.settle).toHaveBeenCalledExactlyOnceWith('reservation', 0.001);
  expect(store.markUnknownCost).not.toHaveBeenCalled();
});

it('still validates tool input before executing it', async () => {
  const { model, input, job } = fixture(() =>
    stream(
      {
        tool_calls: [
          {
            index: 0,
            id: 'bad-call',
            type: 'function',
            function: { name: 'write', arguments: '{"id":42}' }
          }
        ]
      },
      'tool_calls'
    )
  );
  const execute = vi.fn(async () => 'written');
  input.tools = {
    write: tool({ inputSchema: z.object({ id: z.string() }), execute })
  };
  await expect(model.step(job, input)).rejects.toThrow();
  expect(execute).not.toHaveBeenCalled();
});

it('pauses remaining tool calls after asking the user and keeps resumable messages', async () => {
  const { model, input, job } = fixture(() =>
    stream(
      {
        tool_calls: [
          {
            index: 0,
            id: 'ask',
            type: 'function',
            function: { name: 'ask_user', arguments: '{}' }
          },
          {
            index: 1,
            id: 'send',
            type: 'function',
            function: { name: 'send_email', arguments: '{}' }
          }
        ]
      },
      'tool_calls'
    )
  );
  const send = vi.fn(async () => 'Sent');
  input.tools = {
    ask_user: tool({
      inputSchema: z.object({}),
      execute: async () => 'Waiting for an answer'
    }),
    send_email: tool({ inputSchema: z.object({}), execute: send })
  };
  const result = await model.step(job, input);
  expect(result.finished).toBe(false);
  expect(send).not.toHaveBeenCalled();
  expect(result.messages.at(-1)).toMatchObject({
    role: 'tool',
    content: [
      {
        toolCallId: 'send',
        output: {
          type: 'error-text',
          value: 'Waiting for the user’s answer before continuing.'
        }
      }
    ]
  });
});

it.each([400, 401, 402, 403, 404, 422, 429])(
  'releases a confirmed HTTP %s rejection before inference',
  async (status) => {
    const { model, store, input, job } = fixture(() =>
      Response.json(
        {
          error: { message: 'Request rejected', code: status }
        },
        { status }
      )
    );
    await expect(model.step(job, input)).rejects.toThrow();
    expect(store.settle).toHaveBeenCalledWith('reservation', 0, 'rejected');
    expect(store.markUnknownCost).not.toHaveBeenCalled();
  }
);

it.each(['network', 'server', 'search-rejection', 'missing-usage'])(
  'keeps uncertain cost for %s',
  async (failure) => {
    const { model, store, input, job } = fixture(() => {
      if (failure === 'network') throw new Error('Connection lost');
      if (failure === 'missing-usage')
        return stream({ content: 'Done' }, 'stop', null);
      const status = failure === 'server' ? 503 : 404;
      return Response.json(
        { error: { message: 'Unavailable', code: status } },
        { status }
      );
    });
    const request = model.step(job, {
      ...input,
      search: failure === 'search-rejection'
    });
    if (failure === 'missing-usage') await request;
    else await expect(request).rejects.toThrow();
    expect(store.markUnknownCost).toHaveBeenCalledWith('reservation');
    expect(store.settle).not.toHaveBeenCalledWith('reservation', 0, 'rejected');
  }
);

it('records the generation ID before an interrupted stream loses final usage', async () => {
  const { model, store, input, job } = fixture(
    () =>
      new Response(
        new ReadableStream({
          pull(controller) {
            controller.error(new Error('Stream interrupted'));
          }
        }),
        {
          headers: {
            'Content-Type': 'text/event-stream',
            'x-generation-id': 'gen-interrupted'
          }
        }
      )
  );
  await expect(model.step(job, input)).rejects.toThrow();
  expect(store.recordGeneration).toHaveBeenCalledWith(
    'reservation',
    'gen-interrupted'
  );
  expect(store.markUnknownCost).toHaveBeenCalledWith('reservation');
});

it.each(['settled', 'missing', 'pending', 'wrong-id'])(
  'only reconciles verified finished billing records (%s)',
  async (state) => {
    const { model, store } = fixture(() =>
      state === 'missing'
        ? new Response('', { status: 404 })
        : Response.json({
            data: {
              id: state === 'wrong-id' ? 'gen-other' : 'gen-test',
              total_cost: 0.003,
              finish_reason: state === 'pending' ? null : 'stop'
            }
          })
    );
    await model.reconcileCosts!();
    if (state === 'settled')
      expect(store.settle).toHaveBeenCalledWith('reservation', 0.003);
    else expect(store.settle).not.toHaveBeenCalled();
    await model.reconcileCosts!();
    expect(store.costsToReconcile).toHaveBeenCalledTimes(1);
  }
);
