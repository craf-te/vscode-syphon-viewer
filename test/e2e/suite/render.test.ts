import * as assert from 'assert';
import * as path from 'path';
import * as fs from 'fs';
import * as vscode from 'vscode';

/**
 * Verifies that media/view.js puts raw RGBA straight onto the canvas and that
 * not a single byte changes on the way. Lossless transfer is the whole point,
 * so this checks for an exact match rather than a colour resemblance.
 */
suite('Webview rendering', () => {
  let panel: vscode.WebviewPanel | undefined;

  suiteTeardown(() => panel?.dispose());

  test('reproduces received raw RGBA pixel for pixel', async function () {
    this.timeout(60000);

    const extension = vscode.extensions.getExtension('craf-te.syphon-viewer');
    assert.ok(extension, 'extension not found');

    const mediaDir = vscode.Uri.joinPath(extension!.extensionUri, 'media');
    panel = vscode.window.createWebviewPanel(
      'syphonViewer.renderTest',
      'render test',
      { viewColumn: vscode.ViewColumn.One, preserveFocus: true },
      { enableScripts: true, localResourceRoots: [mediaDir] }
    );

    const baseUri = panel.webview.asWebviewUri(mediaDir).toString();
    const template = fs.readFileSync(path.join(mediaDir.fsPath, 'view.html'), 'utf8');

    // acquireVsCodeApi can only be called once per webview, and view.js calls
    // it. Grab it first and shim the function to hand back the same object.
    const probeScript = `
      <script nonce="testnonce">
        const _api = acquireVsCodeApi();
        window.acquireVsCodeApi = () => _api;
        window.addEventListener('message', (e) => {
          if (e.data.type !== 'probe') return;
          setTimeout(() => {
            const c = document.getElementById('canvas');
            const g = c.getContext('2d');
            const d = g.getImageData(0, 0, c.width, c.height).data;
            _api.postMessage({
              type: 'probeResult',
              size: [c.width, c.height],
              pixels: Array.from(d),
            });
          }, 400);
        });
      </script>`;

    panel.webview.html = template
      .replaceAll('{{cspSource}}', panel.webview.cspSource)
      .replaceAll('{{nonce}}', 'testnonce')
      .replaceAll('{{baseUri}}', baseUri)
      .replace('<script nonce="testnonce" src=', probeScript + '\n<script nonce="testnonce" src=');

    // Content any codec would damage: pure colours, hard edges, dense noise
    const W = 16, H = 8;
    const pixels = new Uint8Array(W * H * 4);
    let seed = 20260830;
    for (let i = 0; i < W * H; i++) {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      const o = i * 4;
      pixels[o] = i % 2 === 0 ? 255 : (seed >>> 24) & 0xff;
      pixels[o + 1] = i % 3 === 0 ? 0 : (seed >>> 16) & 0xff;
      pixels[o + 2] = i % 2 === 0 ? 0 : 255;
      pixels[o + 3] = 255;
    }

    const result = new Promise<Record<string, any>>((resolve, reject) => {
      const sub = panel!.webview.onDidReceiveMessage((m) => {
        if (m.type === 'probeResult') {
          sub.dispose();
          resolve(m);
        }
      });
      setTimeout(() => reject(new Error('no render result came back')), 20000);
    });

    await new Promise((r) => setTimeout(r, 800));
    await panel.webview.postMessage({ type: 'status', state: 'connected', name: 'test' });
    await panel.webview.postMessage({ type: 'frame', width: W, height: H, pixels });
    await new Promise((r) => setTimeout(r, 400));
    await panel.webview.postMessage({ type: 'probe' });

    const probe = await result;
    assert.deepStrictEqual(probe.size, [W, H], 'canvas size did not follow the frame');

    const got: number[] = probe.pixels;
    assert.strictEqual(got.length, pixels.length, 'pixel count does not match');

    let maxError = 0;
    let firstBad = -1;
    for (let i = 0; i < pixels.length; i++) {
      const e = Math.abs(got[i] - pixels[i]);
      if (e > maxError) { maxError = e; firstBad = i; }
    }
    assert.strictEqual(
      maxError, 0,
      `not lossless: worst error ${maxError}/255 ` +
      `(byte ${firstBad}: expected ${pixels[firstBad]}, got ${got[firstBad]})`
    );
  });
});
