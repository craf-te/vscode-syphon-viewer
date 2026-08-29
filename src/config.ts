import * as vscode from 'vscode';

export interface SyphonViewerConfig {
  autoConnect: string;
}

const SECTION = 'syphonViewer';

export function readConfig(): SyphonViewerConfig {
  const c = vscode.workspace.getConfiguration(SECTION);
  return {
    autoConnect: c.get<string>('autoConnect', ''),
  };
}

/** Registers a listener invoked when any syphonViewer.* setting changes. */
export function onConfigChange(listener: (config: SyphonViewerConfig) => void): vscode.Disposable {
  return vscode.workspace.onDidChangeConfiguration((event) => {
    if (event.affectsConfiguration(SECTION)) {
      listener(readConfig());
    }
  });
}
