import { z } from 'zod';

export const taskOutputDesignSchema = z.enum([
  'dony',
  'elevenlabs',
  'editorial-cards',
  'acctual',
  'hatch'
]);

export type TaskOutputDesign = z.infer<typeof taskOutputDesignSchema>;

export const taskOutputDesignOptions: ReadonlyArray<{
  value: TaskOutputDesign;
  label: string;
}> = [
  { value: 'dony', label: 'Quiet Neutral' },
  { value: 'elevenlabs', label: 'Warm Editorial' },
  { value: 'editorial-cards', label: 'Editorial Cards' },
  { value: 'acctual', label: 'Crisp Document' },
  { value: 'hatch', label: 'Pastel Zine' }
];

const commonOutputDesignInstructions =
  'Keep the visual design simple and restrained. Treat this as a working document, not a landing page: no marketing navigation, sign-up CTA, social proof, fake controls, decorative metrics, or invented data. Use only system fonts, inline CSS, semantic HTML, and static content; no scripts or external assets. Link directly to underlying sources and never use general web-search result URLs as substitutes for direct links. When the deliverable benefits from a list, prefer a useful breadth of well-supported items instead of stopping at the smallest viable list. Keep gathering while additional items are relevant and trustworthy; stop when they would be weak, repetitive, speculative, or outside scope. Never pad a list or invent entries to make it longer. Keep long-form text readable, tables responsive, links explicit, focus states visible, and print output useful.';

const taskOutputDesignInstructionsByDesign: Record<TaskOutputDesign, string> = {
  dony: 'Use a quiet neutral document language: system typography, restrained light/dark surfaces, 12–16px rounded cards, hairline borders, compact metadata, strong reading hierarchy, and small semantic accents. Prefer one clear reading column and add cards, tables, charts, or columns only when the content benefits.',
  elevenlabs:
    'Use a light warm-cream editorial style: #fdfcfc eggshell canvas, #f5f3f1 taupe surfaces, black ink, whisper-light 32–52px display headings, generous whitespace, 20–24px rounded cards, stone hairlines, and pill-shaped labels. Violet #0447ff and orange #ff4704 may appear only as tiny data or illustrative sparks, never as large fills or ordinary UI chrome.',
  'editorial-cards':
    'Use a light editorial-card style: #fdfcfc off-white paper canvas, #f5f3f1 warm-gray content cards, #171716 ink, weight-400 tightly tracked 36–52px lead headings, a single 880–920px reading column, 20–24px rounded cards with stone #e5e1dd hairlines, and compact outlined metadata pills only when factual scope benefits. Use #0447ff signal blue only for an optional index or compact information cue and #ff4704 signal orange only for an optional implication, caveat, recommendation, or next-step rule. Let the artifact choose its labels, card count, source treatment, and callout wording; do not force a news-brief structure.',
  acctual:
    'Use a light crisp-document style: pure-white canvas, #f7fafc section bands, #1e1e1e ink, #666666 secondary text, tightly tracked geometric system typography, 16px cards, 32px feature panels, cool #ccd1da hairlines, and only slight elevation for one genuine source artifact. Use #0098f2 electric blue for links, key values, or compact callouts; violet and pink may distinguish at most two meaningful categories.',
  hatch:
    'Use a light hand-drawn-zine style: #f5f4f0 cream-paper canvas, white cards with 1px black borders, bold tightly tracked system-serif headings, readable grotesque body text, 16px card radii, generous spacing, and no shadows. Use #99ffcc mint for one key highlight or action, with sky, peach, and pink limited to a few small confetti marks, category chips, or irregular emphasis swashes.'
};

export const taskOutputDesignInstructions = (
  design: TaskOutputDesign
): string =>
  `${taskOutputDesignInstructionsByDesign[design]} ${commonOutputDesignInstructions}`;
