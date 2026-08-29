import * as assert from 'assert';
import * as path from 'path';
import * as fs from 'fs';
import * as vscode from 'vscode';

/**
 * Checks that a narrow panel never needs horizontal scrolling and that the
 * controls stay reachable. Having to scroll sideways to press Connect is a
 * real defect, so measure the layout at several widths.
 */
suite('Narrow panel layout', () => {
  let panel: vscode.WebviewPanel | undefined;
  suiteTeardown(() => panel?.dispose());

  test('no horizontal scroll and controls stay in view as width shrinks', async function () {
    this.timeout(60000);

    const extension = vscode.extensions.getExtension('craf-te.syphon-viewer');
    assert.ok(extension, 'extension not found');
    const mediaDir = vscode.Uri.joinPath(extension!.extensionUri, 'media');

    panel = vscode.window.createWebviewPanel(
      'syphonViewer.narrowTest', 'narrow test',
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
          if (e.data.type !== 'measure') return;
          const widths = e.data.widths;
          const results = [];
          const root = document.documentElement;
          const original = root.style.width;
          for (const w of widths) {
            root.style.width = w + 'px';
            // Force layout to settle
            void root.offsetWidth;
            const select = document.getElementById('server');
            const button = document.getElementById('toggle');
            const stats = document.getElementById('stats');
            results.push({
              width: w,
              bodyScrollWidth: document.body.scrollWidth,
              buttonRight: Math.ceil(button.getBoundingClientRect().right),
              buttonWidth: Math.round(button.getBoundingClientRect().width),
              selectRight: Math.ceil(select.getBoundingClientRect().right),
              statsRight: Math.ceil(stats.getBoundingClientRect().right),
              toolbarHeight: Math.round(document.querySelector('.toolbar').getBoundingClientRect().height),
            });
          }
          root.style.width = original;
          _api.postMessage({ type: 'measured', results });
        });
      </script>`;

    panel.webview.html = template
      .replaceAll('{{cspSource}}', panel.webview.cspSource)
      .replaceAll('{{nonce}}', 'testnonce')
      .replaceAll('{{baseUri}}', baseUri)
      .replace('<script nonce="testnonce" src=', probeScript + '\n<script nonce="testnonce" src=');

    const answer = new Promise<any>((resolve, reject) => {
      const sub = panel!.webview.onDidReceiveMessage((m) => {
        if (m.type === 'measured') { sub.dispose(); resolve(m); }
      });
      setTimeout(() => reject(new Error('no measurement came back')), 20000);
    });

    await new Promise((r) => setTimeout(r, 800));

    // A long server name is the case that used to break the layout
    await panel.webview.postMessage({
      type: 'servers',
      servers: [
        { uuid: 'a', name: 'Composite Out Very Long Server Name', appName: 'TouchDesigner' },
        { uuid: 'b', name: 'Main', appName: 'Resolume Arena' },
      ],
    });
    await panel.webview.postMessage({ type: 'status', state: 'connected', name: 'Composite Out Very Long Server Name' });
    await panel.webview.postMessage({
      type: 'stats', fps: 59.6, kbps: 3_776_000, sourceWidth: 1920, sourceHeight: 1080,
    });
    await new Promise((r) => setTimeout(r, 300));

    const widths = [640, 420, 320, 240, 180];
    await panel.webview.postMessage({ type: 'measure', widths });

    const { results } = await answer;

    for (const r of results) {
      console.log(
        `  ${String(r.width).padStart(4)}px: ` +
        `body=${String(r.bodyScrollWidth).padStart(4)} ` +
        `button.right=${String(r.buttonRight).padStart(4)} (w${r.buttonWidth}) ` +
        `stats.right=${String(r.statsRight).padStart(4)} ` +
        `toolbar.h=${r.toolbarHeight}`
      );
    }

    for (const r of results) {
      assert.ok(
        r.bodyScrollWidth <= r.width + 1,
        `horizontal overflow at ${r.width}px (body=${r.bodyScrollWidth})`
      );
      assert.ok(
        r.buttonRight <= r.width + 1,
        `button is off-screen at ${r.width}px (right=${r.buttonRight})`
      );
      assert.ok(
        r.buttonWidth >= 40,
        `button collapsed at ${r.width}px (width=${r.buttonWidth})`
      );
      assert.ok(
        r.selectRight <= r.width + 1,
        `select is off-screen at ${r.width}px (right=${r.selectRight})`
      );
      assert.ok(
        r.statsRight <= r.width + 1,
        `stats are off-screen at ${r.width}px (right=${r.statsRight})`
      );
    }
  });
});
