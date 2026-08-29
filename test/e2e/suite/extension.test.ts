import * as assert from 'assert';
import { execFileSync } from 'child_process';
import * as vscode from 'vscode';

const EXTENSION_ID = 'craf-te.syphon-viewer';

/** Every tab currently open. */
function allTabs(): readonly vscode.Tab[] {
  return vscode.window.tabGroups.all.flatMap((group) => group.tabs);
}

function findPreviewTab(): vscode.Tab | undefined {
  return allTabs().find((tab) => tab.label === 'Syphon Viewer');
}

/** Webview creation is async, so poll briefly until the condition holds. */
async function waitFor(condition: () => boolean, timeoutMs = 8000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (condition()) return true;
    await new Promise((r) => setTimeout(r, 100));
  }
  return condition();
}

suite('Syphon Viewer extension', () => {

  suiteTeardown(async () => {
    const tab = findPreviewTab();
    if (tab) await vscode.window.tabGroups.close(tab);
  });

  test('activates and registers its command', async () => {
    const extension = vscode.extensions.getExtension(EXTENSION_ID);
    assert.ok(extension, `extension ${EXTENSION_ID} not found`);

    // Contributed commands do not show up in getCommands before activation,
    // so activate explicitly first.
    await extension!.activate();

    const commands = await vscode.commands.getCommands(true);
    assert.ok(
      commands.includes('syphonViewer.open'),
      'syphonViewer.open is not registered'
    );
  });

  test('opening the preview creates a Syphon Viewer tab', async () => {
    assert.strictEqual(findPreviewTab(), undefined, 'a tab was already open');

    await vscode.commands.executeCommand('syphonViewer.open');

    const appeared = await waitFor(() => findPreviewTab() !== undefined);
    assert.ok(appeared, 'the Syphon Viewer tab never appeared');
  });

  test('spawns the helper process from the extension host', async () => {
    // The extension host is an Electron process with a different environment
    // from a normal shell. A live helper proves @rpath/Syphon.framework
    // resolved there, which is the risky part of the whole setup.
    const alive = await waitFor(() => {
      try {
        const out = execFileSync('pgrep', ['-f', 'bin/syphon-bridge'], { encoding: 'utf8' });
        return out.trim().length > 0;
      } catch {
        return false; // pgrep exits 1 when nothing matches
      }
    }, 10000);

    assert.ok(alive, 'the syphon-bridge helper is not running');
  });

  test('reuses the existing tab when run twice', async () => {
    assert.ok(findPreviewTab(), 'the tab from the previous test is gone');
    const before = allTabs().length;

    await vscode.commands.executeCommand('syphonViewer.open');
    await new Promise((r) => setTimeout(r, 1000));

    assert.strictEqual(allTabs().length, before, 'a second preview tab was opened');
  });

  test('closing the tab removes it', async () => {
    const tab = findPreviewTab();
    assert.ok(tab, 'tab not found');

    await vscode.window.tabGroups.close(tab!);

    const gone = await waitFor(() => findPreviewTab() === undefined);
    assert.ok(gone, 'the tab did not close');
  });
});
