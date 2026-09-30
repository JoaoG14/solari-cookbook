import { z } from 'zod';
import { taskScreenshotImportInputSchema } from './tasks';

export const taughtMethodDraftSchema = z.object({
  name: z.string().trim().min(1).max(120),
  whenToUse: z.string().trim().min(1).max(2000),
  instructions: z.string().trim().min(1).max(16000)
});
export type TaughtMethodDraft = z.infer<typeof taughtMethodDraftSchema>;
export const taughtMethodSchema = taughtMethodDraftSchema.extend({
  id: z.string().uuid(),
  taskId: z.string().uuid(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime()
});
export type TaughtMethod = z.infer<typeof taughtMethodSchema>;
export const teachingInputSchema = z.object({
  taskId: z.string().uuid(),
  resultId: z.string().uuid().optional(),
  feedback: z.string().max(16000).optional()
});
export type TeachingInput = z.infer<typeof teachingInputSchema>;
export const teachingAnalysisSchema = z
  .object({
    frames: z
      .array(
        taskScreenshotImportInputSchema.extend({
          seconds: z.number().nonnegative().max(300)
        })
      )
      .min(1)
      .max(60)
  })
  .refine(
    (input) =>
      input.frames.reduce((size, frame) => size + frame.base64.length, 0) <=
      24 * 1024 * 1024,
    'The recording is too large to analyze. Please record a shorter demonstration.'
  );
export type TeachingAnalysis = z.infer<typeof teachingAnalysisSchema>;
export type TeachingContext = TeachingInput & { taskTitle: string };
export type TeachingSource = {
  id: string;
  name: string;
  thumbnail: string;
  appIcon?: string;
};
export const teachingIpcChannels = {
  open: 'teaching:open',
  openChanged: 'teaching:open-changed',
  context: 'teaching:context',
  sources: 'teaching:sources',
  selectSource: 'teaching:select-source',
  recording: 'teaching:recording',
  analyze: 'teaching:analyze',
  save: 'teaching:save',
  cancel: 'teaching:cancel',
  complete: 'teaching:complete',
  list: 'teaching:list',
  update: 'teaching:update',
  delete: 'teaching:delete'
} as const;
export interface TeachingApi {
  open(input?: TeachingInput): Promise<void>;
  onOpenChanged(listener: (open: boolean) => void): () => void;
  context(): Promise<TeachingContext | null>;
  sources(): Promise<TeachingSource[]>;
  selectSource(id: string): Promise<void>;
  recording(active: boolean): Promise<void>;
  analyze(input: TeachingAnalysis): Promise<TaughtMethodDraft>;
  save(draft: TaughtMethodDraft): Promise<TaughtMethod>;
  cancel(): Promise<void>;
  complete(action: 'done' | 'retry'): Promise<void>;
  list(): Promise<TaughtMethod[]>;
  update(id: string, draft: TaughtMethodDraft): Promise<TaughtMethod>;
  delete(id: string): Promise<void>;
}
