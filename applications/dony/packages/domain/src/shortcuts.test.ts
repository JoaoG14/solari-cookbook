import { describe, expect, it } from 'vitest';

import {
  formatShortcutLabel,
  isValidShortcut,
  normalizeShortcut,
  parseShortcut
} from './shortcuts';

describe('shortcuts', () => {
  it('orders modifiers canonically regardless of how they were typed', () => {
    expect(normalizeShortcut('Command+alt+space')).toBe('Alt+Command+Space');
    expect(normalizeShortcut('Shift+Ctrl+k')).toBe('Control+Shift+K');
  });

  it('accepts the aliases Electron and macOS users reach for', () => {
    expect(normalizeShortcut('Option+Cmd+Space')).toBe('Alt+Command+Space');
    expect(normalizeShortcut('Meta+Shift+Return')).toBe('Shift+Command+Return');
  });

  it('rejects shortcuts that would swallow a key system-wide', () => {
    expect(isValidShortcut('Space')).toBe(false);
    expect(isValidShortcut('K')).toBe(false);
    expect(isValidShortcut('Alt')).toBe(false);
  });

  it('rejects malformed accelerators', () => {
    expect(parseShortcut('Alt+Space+K')).toBeNull();
    expect(parseShortcut('Alt+NotAKey')).toBeNull();
    expect(parseShortcut('')).toBeNull();
  });

  it('renders macOS symbols for display', () => {
    expect(formatShortcutLabel('Alt+Command+Space')).toBe('⌥ ⌘ Space');
    expect(formatShortcutLabel('Control+Shift+K')).toBe('⌃ ⇧ K');
    expect(formatShortcutLabel('Command+Return')).toBe('⌘ ↩');
  });

  it('passes an unparseable value through rather than showing nothing', () => {
    expect(formatShortcutLabel('bogus')).toBe('bogus');
  });
});
