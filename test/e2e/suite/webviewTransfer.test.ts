import * as assert from 'assert';
import * as vscode from 'vscode';

/**
 * Verifies the design's assumption that webview.postMessage delivers a
 * Uint8Array with its bytes intact. If that fails, frame data arrives
 * corrupted and nothing renders.
 */
suite('Binary transfer to the webview', () => {
  let panel: vscode.WebviewPanel | undefined;

  suiteTeardown(() => {
    panel?.dispose();
  });

  test('a Uint8Array arrives with its length and bytes intact', async () => {
    panel = vscode.window.createWebviewPanel(
      'syphonViewer.transferTest',
      'transfer test',
      { viewColumn: vscode.ViewColumn.One, preserveFocus: true },
      { enableScripts: true }
    );

    panel.webview.html = `
      <script>
        const vscode = acquireVsCodeApi();
        window.addEventListener('message', (e) => {
          const p = e.data.payload;
          vscode.postMessage({
            isUint8Array: p instanceof Uint8Array,
            length: p && p.length,
            ctor: p && p.constructor && p.constructor.name,
            first4: p ? Array.from(p).slice(0, 4) : null,
          });
        });
        vscode.postMessage({ ready: true });
      </script>`;

    const ready = new Promise<void>((resolve) => {
      const sub = panel!.webview.onDidReceiveMessage((m) => {
        if (m.ready) {
          sub.dispose();
          resolve();
        }
      });
    });
    await ready;

    const sample = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x11, 0x22, 0x33]);
    const echoed = new Promise<Record<string, unknown>>((resolve) => {
      const sub = panel!.webview.onDidReceiveMessage((m) => {
        sub.dispose();
        resolve(m);
      });
    });

    await panel.webview.postMessage({ payload: sample });
    const result = (await Promise.race([
      echoed,
      new Promise((_, reject) => setTimeout(() => reject(new Error('timed out')), 8000)),
    ])) as Record<string, unknown>;

    assert.strictEqual(result.length, sample.length,
      `length changed (ctor=${result.ctor})`);
    assert.deepStrictEqual(result.first4, [0xff, 0xd8, 0xff, 0xe0],
      `leading bytes were corrupted (ctor=${result.ctor})`);
    assert.strictEqual(result.isUint8Array, true,
      `did not arrive as a Uint8Array (ctor=${result.ctor})`);
  });
});
