import { spawn, ChildProcess } from 'child_process';
import { EventEmitter } from 'events';
import { MessageDecoder, ProtocolError, HelperMessage } from './protocol';

export interface HelperProcessOptions {
  /** Binary to run, normally bin/syphon-bridge. */
  binaryPath: string;
  /** Extra arguments, used by tests to run a node script instead. */
  extraArgs?: string[];
  /** How many automatic restarts to attempt. */
  maxRestarts?: number;
  /** Delay before each restart, in ms. The last entry repeats if the list is short. */
  backoffMs?: number[];
  /** Where diagnostic logs go. */
  log?: (message: string) => void;
}

/**
 * Runs the helper binary and manages its stdio.
 * It does not import vscode, so unit tests can drive it directly.
 *
 * Events:
 *   'message' (m: HelperMessage)   a message from the helper
 *   'exit'    (code: number|null)  the helper exited
 *   'giveUp'  (reason: string)     restarts were abandoned
 */
export class HelperProcess extends EventEmitter {
  private child: ChildProcess | undefined;
  private decoder = new MessageDecoder();
  private recentStderr: string[] = [];
  private restarts = 0;
  private disposed = false;
  private restartTimer: NodeJS.Timeout | undefined;

  private readonly maxRestarts: number;
  private readonly backoffMs: number[];
  private readonly log: (message: string) => void;

  constructor(private readonly options: HelperProcessOptions) {
    super();
    this.maxRestarts = options.maxRestarts ?? 3;
    this.backoffMs = options.backoffMs ?? [1000, 2000, 4000];
    this.log = options.log ?? (() => {});
  }

  get running(): boolean {
    return this.child !== undefined && this.child.exitCode === null;
  }

  start(): void {
    if (this.disposed || this.child) return;
    this.spawnChild();
  }

  /** Sends a command to the helper as one JSON line. */
  send(cmd: Record<string, unknown>): void {
    if (!this.child?.stdin?.writable) return;
    this.child.stdin.write(JSON.stringify(cmd) + '\n');
  }

  dispose(): void {
    this.disposed = true;
    if (this.restartTimer) {
      clearTimeout(this.restartTimer);
      this.restartTimer = undefined;
    }
    const child = this.child;
    this.child = undefined;
    if (child) {
      child.stdout?.removeAllListeners();
      child.stderr?.removeAllListeners();
      child.removeAllListeners();
      child.kill('SIGTERM');
    }
    this.removeAllListeners();
  }

  private spawnChild(): void {
    const args = this.options.extraArgs ?? [];
    this.log(`Starting helper: ${this.options.binaryPath} ${args.join(' ')}`);

    const child = spawn(this.options.binaryPath, args, {
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    this.child = child;
    this.decoder = new MessageDecoder();

    child.stdout?.on('data', (chunk: Buffer) => {
      try {
        for (const message of this.decoder.push(new Uint8Array(chunk))) {
          this.emit('message', message);
        }
      } catch (error) {
        if (error instanceof ProtocolError) {
          this.log(`Protocol violation, restarting helper: ${error.message}`);
          child.kill('SIGKILL');
          return;
        }
        throw error;
      }
    });

    child.stderr?.on('data', (chunk: Buffer) => {
      const text = chunk.toString().trimEnd();
      this.log(`[helper] ${text}`);
      // Keep a little recent stderr around to guess at causes later.
      this.recentStderr.push(text);
      if (this.recentStderr.length > 20) this.recentStderr.shift();
    });

    child.on('error', (error) => {
      this.log(`Failed to start helper: ${error.message}`);
    });

    child.on('exit', (code) => {
      if (this.child !== child) return; // already disposed
      this.child = undefined;
      this.emit('exit', code);
      if (this.disposed) return;
      this.scheduleRestart(code);
    });
  }

  private scheduleRestart(code: number | null): void {
    if (this.restarts >= this.maxRestarts) {
      const reason =
        `Helper keeps exiting (last exit code: ${code}). ` +
        `Gave up after ${this.maxRestarts} restarts.` +
        this.diagnosticHint();
      this.log(reason);
      this.emit('giveUp', reason);
      return;
    }

    const delay = this.backoffMs[Math.min(this.restarts, this.backoffMs.length - 1)];
    this.restarts += 1;
    this.log(`Restarting helper in ${delay}ms (${this.restarts}/${this.maxRestarts})`);

    this.restartTimer = setTimeout(() => {
      this.restartTimer = undefined;
      if (!this.disposed) this.spawnChild();
    }, delay);
  }

  /**
   * Guesses at a common cause from stderr and appends one line of advice.
   * A dyld load failure almost always means Syphon.framework is missing or
   * that Gatekeeper rejected it over a quarantine attribute.
   */
  private diagnosticHint(): string {
    const text = this.recentStderr.join('\n');
    if (/Library not loaded|code signature|Gatekeeper/i.test(text)) {
      return (
        ' Syphon.framework may not be loading. In the extension folder, run: ' +
        'xattr -dr com.apple.quarantine bin/syphon-bridge Frameworks/Syphon.framework'
      );
    }
    return '';
  }
}
