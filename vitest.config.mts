import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    // E2E needs a real VS Code, so keep it out of vitest.
    exclude: ['test/e2e/**'],
    environment: 'node',
  },
});
