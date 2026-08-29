import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import { HelperProcess } from './HelperProcess';
import { HelperMessage } from './protocol';
import { readConfig, onConfigChange } from './config';

interface ServerInfo {
  uuid: string;
  name: string;
  appName: string;
}

export class SyphonViewerPanel {
  private static current: SyphonViewerPanel | undefined;
  private static readonly viewType = 'syphonViewer.preview';

  private readonly disposables: vscode.Disposable[] = [];
  private readonly helper: HelperProcess;
  private readonly output: vscode.OutputChannel;

  private servers: ServerInfo[] = [];
  private webviewReady = false;
  private connectedUuid: string | undefined;
  /** Name of a server we lost; reconnect if one with the same name returns. */
  private reconnectTargetName: string | undefined;

  static createOrShow(context: vscode.ExtensionContext): void {
    if (process.platform !== 'darwin' || process.arch !== 'arm64') {
      vscode.window.showErrorMessage('Syphon Viewer requires macOS on Apple Silicon.');
      return;
    }

    if (SyphonViewerPanel.current) {
      SyphonViewerPanel.current.panel.reveal(vscode.ViewColumn.Beside);
      return;
    }

    const panel = vscode.window.createWebviewPanel(
      SyphonViewerPanel.viewType,
      'Syphon Viewer',
      vscode.ViewColumn.Beside,
      {
        enableScripts: true,
        localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, 'media')],
      }
    );
    SyphonViewerPanel.current = new SyphonViewerPanel(panel, context);
  }

  private constructor(
    private readonly panel: vscode.WebviewPanel,
    private readonly context: vscode.ExtensionContext
  ) {
    this.output = vscode.window.createOutputChannel('Syphon Viewer');
    this.disposables.push(this.output);

    this.helper = new HelperProcess({
      binaryPath: path.join(context.extensionPath, 'bin', 'syphon-bridge'),
      log: (message) => this.output.appendLine(message),
    });

    this.panel.webview.html = this.buildHtml();
    this.wireWebview();
    this.wireHelper();
    this.wireVisibility();

    this.disposables.push(
      // autoConnect is re-read on the next server list, so just nudge a
      // re-evaluation here.
      onConfigChange(() => this.tryAutoConnect())
    );

    this.panel.onDidDispose(() => this.dispose(), null, this.disposables);
    this.helper.start();
  }

  dispose(): void {
    SyphonViewerPanel.current = undefined;
    this.helper.dispose();
    this.disposables.forEach((d) => d.dispose());
    this.disposables.length = 0;
    this.panel.dispose();
  }

  private wireWebview(): void {
    this.disposables.push(
      this.panel.webview.onDidReceiveMessage((message) => {
        switch (message.type) {
          case 'ready':
            this.webviewReady = true;
            this.post({ type: 'servers', servers: this.servers });
            break;
          case 'connect':
            this.post({ type: 'status', state: 'connecting' });
            this.helper.send({ cmd: 'connect', uuid: message.uuid });
            break;
          case 'disconnect':
            this.reconnectTargetName = undefined;
            this.helper.send({ cmd: 'disconnect' });
            break;
        }
      })
    );
  }

  private wireHelper(): void {
    this.helper.on('message', (message: HelperMessage) => {
      if (message.kind === 'frame') {
        this.post({
          type: 'frame',
          width: message.width,
          height: message.height,
          pixels: message.pixels,
        });
        return;
      }
      this.handleControl(message.json as Record<string, unknown>);
    });

    this.helper.on('giveUp', (reason: string) => {
      this.post({ type: 'status', state: 'error', message: reason });
    });
  }

  private handleControl(event: Record<string, unknown>): void {
    switch (event.event) {
      case 'hello':
        break;

      case 'servers': {
        this.servers = (event.servers as ServerInfo[]) ?? [];
        this.post({ type: 'servers', servers: this.servers });
        this.tryAutoConnect();
        break;
      }

      case 'connected':
        this.connectedUuid = event.uuid as string;
        this.reconnectTargetName = event.name as string;
        this.post({ type: 'status', state: 'connected', name: event.name });
        break;

      case 'disconnected': {
        this.connectedUuid = undefined;
        const reason = event.reason as string;
        if (reason === 'requested') {
          this.reconnectTargetName = undefined;
          this.post({ type: 'status', state: 'idle', message: 'Not connected' });
        } else {
          this.post({ type: 'status', state: 'idle', message: 'Disconnected. Waiting…' });
        }
        break;
      }

      case 'error':
        this.output.appendLine(`helper error: ${event.code} ${event.message}`);
        this.post({ type: 'status', state: 'error', message: String(event.message) });
        break;

      case 'stats':
        this.post({
          type: 'stats',
          fps: event.fps,
          kbps: event.kbps,
          sourceWidth: event.sourceWidth,
          sourceHeight: event.sourceHeight,
        });
        break;
    }
  }

  /**
   * Connects when the list contains the autoConnect target, or a server with
   * the same name as one we were disconnected from.
   */
  private tryAutoConnect(): void {
    if (this.connectedUuid) return;

    const target = this.reconnectTargetName ?? readConfig().autoConnect;
    if (!target) return;

    const match = this.servers.find((s) => s.name === target);
    if (!match) return;

    this.output.appendLine(`Auto-connecting to ${target}`);
    this.helper.send({ cmd: 'connect', uuid: match.uuid });
  }

  private wireVisibility(): void {
    this.disposables.push(
      this.panel.onDidChangeViewState(() => {
        // Stop the helper's work while the tab is in the background.
        this.helper.send({ cmd: this.panel.visible ? 'resume' : 'pause' });
      })
    );
  }

  private post(message: Record<string, unknown>): void {
    if (!this.webviewReady && message.type !== 'servers') return;
    void this.panel.webview.postMessage(message);
  }

  private buildHtml(): string {
    const mediaUri = vscode.Uri.joinPath(this.context.extensionUri, 'media');
    const baseUri = this.panel.webview.asWebviewUri(mediaUri);
    const nonce = Array.from({ length: 32 }, () =>
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'.charAt(
        Math.floor(Math.random() * 62)
      )
    ).join('');

    const template = fs.readFileSync(path.join(mediaUri.fsPath, 'view.html'), 'utf8');
    return template
      .replaceAll('{{cspSource}}', this.panel.webview.cspSource)
      .replaceAll('{{nonce}}', nonce)
      .replaceAll('{{baseUri}}', baseUri.toString());
  }
}
