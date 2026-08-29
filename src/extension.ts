import * as vscode from 'vscode';
import { SyphonViewerPanel } from './SyphonViewerPanel';

export function activate(context: vscode.ExtensionContext) {
  context.subscriptions.push(
    vscode.commands.registerCommand('syphonViewer.open', () => {
      SyphonViewerPanel.createOrShow(context);
    })
  );
}

export function deactivate() {}
