import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/index.ts'],
  format: ['esm'],
  outDir: 'dist',
  platform: 'node',
  target: 'node20',
  noExternal: ['@dony/domain'],
  sourcemap: true,
  clean: true,
  dts: false,
  splitting: false
});
