import * as assert from 'assert';
import * as path from 'path';
import * as fs from 'fs';
import * as vscode from 'vscode';

/**
 * Checks in a real webview that the size/fps/bandwidth line sits below the
 * video and reads small. Position and type size are the requirement itself, so
 * measure the rendered result rather than trusting the stylesheet.
 */
suite('Layout', () => {
  let panel: vscode.WebviewPanel | undefined;
  suiteTeardown(() => panel?.dispose());

  test('stats read small and sit below the video', async function () {
    this.timeout(60000);

    const extension = vscode.extensions.getExtension('craf-te.syphon-viewer');
    assert.ok(extension, 'extension not found');
    const mediaDir = vscode.Uri.joinPath(extension!.extensionUri, 'media');

    panel = vscode.window.createWebviewPanel(
      'syphonViewer.layoutTest', 'layout test',
      { viewColumn: vscode.ViewColumn.One, preserveFocus: true },
      { enableScripts: true, localResourceRoots: [mediaDir] }
    );

    const baseUri = panel.webview.asWebviewUri(mediaDir).toString();
    const template = fs.readFileSync(path.join(mediaDir.fsPath, 'view.html'), 'utf8');

    const probeScript = `
      <script nonce="testnonce">
        const _api = acquireVsCodeApi();
        window.acquireVsCodeApi = () => _api;
        window.addEventListener('message', (e) => {
          if (e.data.type !== 'probe') return;
          setTimeout(() => {
            const stats = document.getElementById('stats');
            const canvas = document.getElementById('canvas');
            const toolbar = document.querySelector('.toolbar');
            const cs = getComputedStyle(stats);
            const body = getComputedStyle(document.body);
            _api.postMessage({
              type: 'probeResult',
              text: stats.textContent,
              statsTop: stats.getBoundingClientRect().top,
              canvasBottom: canvas.getBoundingClientRect().bottom,
              toolbarBottom: toolbar.getBoundingClientRect().bottom,
              fontPx: parseFloat(cs.fontSize),
              bodyFontPx: parseFloat(body.fontSize),
              opacity: parseFloat(cs.opacity),
            });
          }, 300);
        });
      </script>`;

    panel.webview.html = template
      .replaceAll('{{cspSource}}', panel.webview.cspSource)
      .replaceAll('{{nonce}}', 'testnonce')
      .replaceAll('{{baseUri}}', baseUri)
      .replace('<script nonce="testnonce" src=', probeScript + '\n<script nonce="testnonce" src=');

    const result = new Promise<any>((resolve, reject) => {
      const sub = panel!.webview.onDidReceiveMessage((m) => {
        if (m.type === 'probeResult') { sub.dispose(); resolve(m); }
      });
      setTimeout(() => reject(new Error('no measurement came back')), 20000);
    });

    await new Promise((r) => setTimeout(r, 800));
    // Connect, draw one frame, then push stats in
    await panel.webview.postMessage({ type: 'status', state: 'connected', name: 'test' });
    const W = 32, H = 18;
    await panel.webview.postMessage({
      type: 'frame', width: W, height: H,
      pixels: new Uint8Array(W * H * 4).fill(128),
    });
    await panel.webview.postMessage({
      type: 'stats', fps: 30, kbps: 1_992_000, sourceWidth: 1920, sourceHeight: 1080,
    });
    await new Promise((r) => setTimeout(r, 300));
    await panel.webview.postMessage({ type: 'probe' });

    const p = await result;

    assert.ok(p.text && p.text.length > 0, 'no stats shown');
    assert.match(p.text, /1920×1080/, `resolution missing: ${p.text}`);
    assert.match(p.text, /30\.0 fps/, `fps missing: ${p.text}`);
    assert.match(p.text, /MB\/s/, `bandwidth missing: ${p.text}`);

    assert.ok(
      p.statsTop >= p.canvasBottom,
      `not below the video (stats.top=${p.statsTop}, canvas.bottom=${p.canvasBottom})`
    );
    assert.ok(
      p.statsTop > p.toolbarBottom,
      `still in the toolbar (stats.top=${p.statsTop}, toolbar.bottom=${p.toolbarBottom})`
    );
    assert.ok(
      p.fontPx < p.bodyFontPx,
      `not smaller than body text (stats=${p.fontPx}px, body=${p.bodyFontPx}px)`
    );
    assert.ok(p.opacity < 1, `not visually subdued (opacity=${p.opacity})`);

    console.log(
      `  text: "${p.text}"  font=${p.fontPx}px (body ${p.bodyFontPx}px)  ` +
      `opacity=${p.opacity}  canvas.bottom=${p.canvasBottom.toFixed(0)} stats.top=${p.statsTop.toFixed(0)}`
    );
  });
});
