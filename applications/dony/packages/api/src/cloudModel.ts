import { createOpenRouter } from '@openrouter/ai-sdk-provider';
import {
  chatThinkingEffort,
  chatThinkingModel,
  type ChatThinking
} from '@dony/domain';
import {
  APICallError,
  asSchema,
  ToolLoopAgent,
  isStepCount,
  type ModelMessage,
  type ToolSet
} from 'ai';
import { z } from 'zod';
import { CloudError } from './cloudCommands';
import type { CloudJob, CloudStore } from './cloudStore';

const modelSchema = z.object({
  id: z.string(),
  context_length: z.number().positive(),
  pricing: z.object({
    prompt: z.coerce.number().nonnegative(),
    completion: z.coerce.number().nonnegative(),
    request: z.coerce.number().nonnegative().optional()
  }),
  supported_parameters: z.array(z.string()),
  reasoning: z
    .object({
      supported_efforts: z.array(z.string()).nullable().optional()
    })
    .optional()
});
const maxOutputTokens = 8192;
export type CloudModelStep = {
  messages: ModelMessage[];
  text: string;
  finished: boolean;
};
export type CloudModel = {
  configured: boolean;
  reconcileCosts?(): Promise<void>;
  step(
    job: CloudJob,
    input: {
      instructions: string;
      messages: ModelMessage[];
      tools: ToolSet;
      signal: AbortSignal;
      search?: boolean;
      thinking?: ChatThinking;
      onText?: (text: string) => Promise<void>;
    }
  ): Promise<CloudModelStep>;
};

export function createCloudModel(
  store: CloudStore,
  options: { apiKey?: string; model?: string }
): CloudModel {
  const modelId = options.model ?? 'openai/gpt-5.4-mini';
  let catalog:
    { expires: number; models: z.infer<typeof modelSchema>[] } | undefined;
  let nextReconciliation = 0;
  return {
    configured: Boolean(options.apiKey),
    async reconcileCosts() {
      if (!options.apiKey || Date.now() < nextReconciliation) return;
      nextReconciliation = Date.now() + 60_000;
      for (const pending of await store.costsToReconcile()) {
        try {
          const response = await fetch(
            `https://openrouter.ai/api/v1/generation?id=${encodeURIComponent(pending.generation_id)}`,
            {
              headers: { Authorization: `Bearer ${options.apiKey}` },
              signal: AbortSignal.timeout(5_000)
            }
          );
          if (!response.ok) continue;
          const record = z
            .object({
              data: z.object({
                id: z.string(),
                total_cost: z.number().nonnegative(),
                finish_reason: z.string().nullable(),
                cancelled: z.boolean().optional()
              })
            })
            .safeParse(await response.json());
          if (!record.success || record.data.data.id !== pending.generation_id)
            continue;
          const usage = record.data.data;
          if (usage.finish_reason !== null || usage.cancelled)
            await store.settle(pending.id, usage.total_cost);
        } catch {
          // Keep the hold when billing evidence is unavailable. Retry later.
        }
      }
    },
    async step(job, input) {
      if (!options.apiKey)
        throw new CloudError(
          503,
          'Dony is temporarily unavailable. Please try again later.'
        );
      if (!catalog || catalog.expires < Date.now()) {
        const response = await fetch('https://openrouter.ai/api/v1/models', {
          signal: AbortSignal.timeout(15_000)
        });
        if (!response.ok)
          throw new CloudError(
            503,
            'Dony cannot start right now. Please try again in a few minutes.'
          );
        const body = z
          .object({ data: z.array(z.object({ id: z.string() }).passthrough()) })
          .parse(await response.json());
        const models = body.data.flatMap((item) => {
          const parsed = modelSchema.safeParse(item);
          return parsed.success &&
            parsed.data.supported_parameters.includes('tools')
            ? [parsed.data]
            : [];
        });
        catalog = { expires: Date.now() + 5 * 60_000, models };
      }
      const selectedId = input.thinking
        ? chatThinkingModel(
            input.thinking,
            catalog.models.map((model) => model.id),
            modelId
          )
        : modelId;
      const model = catalog.models.find((model) => model.id === selectedId);
      if (!model)
        throw new CloudError(
          503,
          'Dony is temporarily unavailable. Please try again later.'
        );
      const requestedEffort = input.thinking
        ? chatThinkingEffort[input.thinking]
        : undefined;
      const supportedEfforts = model.reasoning?.supported_efforts;
      const effort =
        requestedEffort &&
        supportedEfforts &&
        !supportedEfforts.includes(requestedEffort)
          ? (['high', 'medium', 'low'] as const).find((value) =>
              supportedEfforts.includes(value)
            )
          : requestedEffort;
      const schemas = await Promise.all(
        Object.entries(input.tools).map(async ([name, definition]) => ({
          name,
          description: definition.description,
          parameters: await asSchema(definition.inputSchema).jsonSchema
        }))
      );
      // One token per UTF-8 byte, plus framing overhead, is deliberately generous
      // for text while scaling with the actual request rather than model capacity.
      const requestBytes = Buffer.byteLength(
        JSON.stringify({
          instructions: input.instructions,
          messages: input.messages,
          tools: schemas
        })
      );
      const hasMedia = input.messages.some(
        (message) =>
          Array.isArray(message.content) &&
          message.content.some(
            (part) => part.type === 'image' || part.type === 'file'
          )
      );
      // File expansion and injected search results are opaque to this service.
      // Keep their full input bound until the provider exposes a hard size limit.
      const inputTokens =
        input.search || hasMedia
          ? model.context_length
          : Math.min(
              model.context_length,
              Math.ceil(requestBytes * 1.1) + 2048 + input.messages.length * 256
            );
      const reservation = await store.reserve(
        job,
        inputTokens * model.pricing.prompt +
          maxOutputTokens * model.pricing.completion +
          (model.pricing.request ?? 0) +
          (input.search ? 0.05 : 0)
      );
      let requestStarted = false;
      let responseStatus: number | undefined;
      let generationId: string | undefined;
      let settled = false;
      const openrouter = createOpenRouter({
        apiKey: options.apiKey,
        headers: { 'X-Title': 'Dony' },
        fetch: async (url, init) => {
          requestStarted = true;
          const response = await fetch(url, init);
          responseStatus = response.status;
          const responseId = response.headers.get('x-generation-id');
          if (responseId) {
            generationId = responseId;
            await store.recordGeneration(reservation, responseId);
          }
          return response;
        }
      });
      try {
        const agent = new ToolLoopAgent({
          model: openrouter(model.id, {
            usage: { include: true },
            ...(effort && model.supported_parameters.includes('reasoning')
              ? { reasoning: { effort } }
              : {}),
            ...(model.supported_parameters.includes('parallel_tool_calls')
              ? { parallelToolCalls: false }
              : {}),
            provider: {
              require_parameters: true,
              max_price: {
                prompt: model.pricing.prompt * 1_000_000,
                completion: model.pricing.completion * 1_000_000,
                request: model.pricing.request ?? 0
              }
            },
            ...(input.search
              ? {
                  plugins: [
                    {
                      id: 'web' as const,
                      engine: 'exa' as const,
                      max_results: 5
                    }
                  ]
                }
              : {})
          }),
          instructions: input.instructions,
          // Get validated tool requests, then execute only after settling this call.
          tools: Object.fromEntries(
            schemas.map(({ name, description }) => [
              name,
              {
                inputSchema: asSchema(input.tools[name]!.inputSchema),
                ...(description ? { description } : {})
              }
            ])
          ),
          stopWhen: isStepCount(1),
          maxOutputTokens,
          maxRetries: 0
        });
        const result = await agent.stream({
          messages: input.messages,
          abortSignal: input.signal
        });
        let text = '';
        let updated = 0;
        for await (const part of result.fullStream) {
          if (part.type === 'error') throw part.error;
          if (part.type !== 'text-delta') continue;
          text += part.text;
          if (input.onText && Date.now() - updated > 500) {
            updated = Date.now();
            await input.onText(text);
          }
        }
        const metadata = await result.providerMetadata;
        const usage = metadata?.openrouter?.usage as
          { cost?: number } | undefined;
        const responseId = (await result.response).id;
        if (!generationId && responseId)
          await store.recordGeneration(reservation, responseId);
        await store.settle(reservation, usage?.cost);
        if (
          typeof usage?.cost !== 'number' ||
          !Number.isFinite(usage.cost) ||
          usage.cost < 0
        )
          await store.markUnknownCost(reservation);
        settled = true;
        const reason = await result.finishReason;
        if (reason !== 'stop' && reason !== 'tool-calls')
          throw new CloudError(
            503,
            'Dony couldn’t finish this response. Please try again, or ask for a smaller part of the task.'
          );
        const messages: ModelMessage[] = [
          ...input.messages,
          ...(await result.responseMessages)
        ];
        const calls = await result.toolCalls;
        let awaitingAnswer = false;
        for (const call of calls) {
          input.signal.throwIfAborted();
          if (awaitingAnswer) {
            messages.push({
              role: 'tool',
              content: [
                {
                  type: 'tool-result',
                  toolCallId: call.toolCallId,
                  toolName: call.toolName,
                  output: {
                    type: 'error-text',
                    value: 'Waiting for the user’s answer before continuing.'
                  }
                }
              ]
            });
            continue;
          }
          if (call.invalid)
            throw new CloudError(
              503,
              'Dony couldn’t complete this step. Please try again.'
            );
          const execute = input.tools[call.toolName]?.execute;
          if (!execute || call.providerExecuted) continue;
          // Propagate failures to the worker. A tool error is not completed work.
          const output: unknown = await execute(call.input, {
            toolCallId: call.toolCallId,
            messages,
            abortSignal: input.signal,
            context: undefined
          });
          messages.push({
            role: 'tool',
            content: [
              {
                type: 'tool-result',
                toolCallId: call.toolCallId,
                toolName: call.toolName,
                output: {
                  type: 'json',
                  value: z
                    .json()
                    .parse(JSON.parse(JSON.stringify(output ?? null)))
                }
              }
            ]
          });
          awaitingAnswer = call.toolName === 'ask_user';
        }
        return {
          text,
          messages,
          finished: reason === 'stop' && calls.length === 0
        };
      } catch (error) {
        if (!settled) {
          // Only explicit pre-generation rejections prove there was no inference.
          // A search request may already have incurred a search fee, so reconcile it.
          const rejected =
            !input.search &&
            !hasMedia &&
            APICallError.isInstance(error) &&
            responseStatus === error.statusCode &&
            [400, 401, 402, 403, 404, 422, 429].includes(error.statusCode ?? 0);
          if (!requestStarted || rejected)
            await store.settle(reservation, 0, 'rejected');
          else await store.markUnknownCost(reservation);
        }
        throw error;
      }
    }
  };
}
