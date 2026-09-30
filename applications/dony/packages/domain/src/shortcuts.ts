import { z } from 'zod';

// Electron accelerators are the storage format, so main can hand the string
// straight to `globalShortcut.register` and the renderer only has to render it.
export const shortcutModifiers = [
  'Control',
  'Alt',
  'Shift',
  'Command'
] as const;

export type ShortcutModifier = (typeof shortcutModifiers)[number];

const modifierOrder: readonly ShortcutModifier[] = [
  'Control',
  'Alt',
  'Shift',
  'Command'
];

const modifierSymbols: Record<ShortcutModifier, string> = {
  Control: '⌃',
  Alt: '⌥',
  Shift: '⇧',
  Command: '⌘'
};

const functionKeys = Array.from({ length: 24 }, (_, index) => `F${index + 1}`);

const namedKeys = [
  'Space',
  'Tab',
  'Backspace',
  'Delete',
  'Insert',
  'Return',
  'Up',
  'Down',
  'Left',
  'Right',
  'Home',
  'End',
  'PageUp',
  'PageDown',
  'Escape',
  'Plus',
  'numdec',
  'numadd',
  'numsub',
  'nummult',
  'numdiv'
] as const;

// Single characters Electron accepts verbatim, plus the named keys above.
const punctuationKeys = [
  '`',
  '-',
  '=',
  '[',
  ']',
  '\\',
  ';',
  "'",
  ',',
  '.',
  '/'
] as const;

const isSupportedKey = (key: string): boolean => {
  if (/^[0-9A-Z]$/.test(key)) {
    return true;
  }

  return (
    functionKeys.includes(key) ||
    (namedKeys as readonly string[]).includes(key) ||
    (punctuationKeys as readonly string[]).includes(key)
  );
};

export type ParsedShortcut = {
  modifiers: ShortcutModifier[];
  key: string;
};

const normalizeModifier = (token: string): ShortcutModifier | null => {
  switch (token.toLowerCase()) {
    case 'control':
    case 'ctrl':
      return 'Control';
    case 'alt':
    case 'option':
      return 'Alt';
    case 'shift':
      return 'Shift';
    case 'command':
    case 'cmd':
    case 'super':
    case 'meta':
      return 'Command';
    default:
      return null;
  }
};

const normalizeKey = (token: string): string | null => {
  if (token.length === 1) {
    const upper = token.toUpperCase();

    return isSupportedKey(upper) ? upper : isSupportedKey(token) ? token : null;
  }

  const match = [...functionKeys, ...namedKeys].find(
    (candidate) => candidate.toLowerCase() === token.toLowerCase()
  );

  return match ?? null;
};

export const parseShortcut = (accelerator: string): ParsedShortcut | null => {
  const tokens = accelerator
    .split('+')
    .map((token) => token.trim())
    .filter((token) => token.length > 0);

  if (tokens.length < 2) {
    return null;
  }

  const modifiers = new Set<ShortcutModifier>();
  let key: string | null = null;

  for (const token of tokens) {
    const modifier = normalizeModifier(token);

    if (modifier) {
      modifiers.add(modifier);
      continue;
    }

    if (key !== null) {
      return null;
    }

    key = normalizeKey(token);

    if (key === null) {
      return null;
    }
  }

  // A global shortcut without a modifier would swallow the key system-wide.
  if (key === null || modifiers.size === 0) {
    return null;
  }

  return {
    modifiers: modifierOrder.filter((modifier) => modifiers.has(modifier)),
    key
  };
};

export const isValidShortcut = (accelerator: string): boolean =>
  parseShortcut(accelerator) !== null;

export const formatShortcutAccelerator = (
  shortcut: ParsedShortcut
): string => [...shortcut.modifiers, shortcut.key].join('+');

/** Normalizes any accepted spelling into Electron's canonical accelerator. */
export const normalizeShortcut = (accelerator: string): string | null => {
  const parsed = parseShortcut(accelerator);

  return parsed ? formatShortcutAccelerator(parsed) : null;
};

const keyLabels: Record<string, string> = {
  Space: 'Space',
  Return: '↩',
  Tab: '⇥',
  Backspace: '⌫',
  Delete: '⌦',
  Escape: '⎋',
  Up: '↑',
  Down: '↓',
  Left: '←',
  Right: '→',
  PageUp: '⇞',
  PageDown: '⇟',
  Home: '↖',
  End: '↘'
};

/** Human-readable label, e.g. `Alt+Command+Space` -> `⌥ ⌘ Space`. */
export const formatShortcutLabel = (accelerator: string): string => {
  const parsed = parseShortcut(accelerator);

  if (!parsed) {
    return accelerator;
  }

  return [
    ...parsed.modifiers.map((modifier) => modifierSymbols[modifier]),
    keyLabels[parsed.key] ?? parsed.key
  ].join(' ');
};

export const shortcutAcceleratorSchema = z
  .string()
  .refine(isValidShortcut, 'Expected a shortcut with at least one modifier.');
