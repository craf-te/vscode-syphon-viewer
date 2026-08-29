import * as path from 'path';
import { runTests } from '@vscode/test-electron';

async function main(): Promise<void> {
  // Three levels up from out/test/e2e is the repository root.
  const extensionDevelopmentPath = path.resolve(__dirname, '../../../');
  const extensionTestsPath = path.resolve(__dirname, './suite/index');

  await runTests({
    extensionDevelopmentPath,
    extensionTestsPath,
    // Keep user settings and other extensions out of the run.
    launchArgs: ['--disable-extensions', '--disable-gpu'],
  });
}

main().catch((error) => {
  console.error('E2E run failed', error);
  process.exit(1);
});
