import { describe, it, expect, afterEach } from 'vitest';
import * as path from 'path';
import { HelperProcess } from '../src/HelperProcess';
import type { HelperMessage } from '../src/protocol';

// import.meta clashes with the CommonJS output in tsconfig, so avoid it.
// vitest runs with the project root as cwd.
const FAKE = path.resolve(process.cwd(), 'test', 'fixtures', 'fakeHelper.mjs');

const created: HelperProcess[] = [];

function make(args: string[], overrides: Record<string, unknown> = {}) {
  const h = new HelperProcess({
    binaryPath: process.execPath,
    extraArgs: [FAKE, ...args],
    ...overrides,
  });
  created.push(h);
  return h;
}

function nextMessage(h: HelperProcess, predicate: (m: HelperMessage) => boolean, ms = 5000) {
  return new Promise<HelperMessage>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timed out')), ms);
    h.on('message', (m: HelperMessage) => {
      if (predicate(m)) {
        clearTimeout(timer);
        resolve(m);
      }
    });
  });
}

afterEach(() => {
  created.splice(0).forEach((h) => h.dispose());
});

describe('HelperProcess', () => {
  it('receives a control message from the helper', async () => {
    const h = make(['--hello']);
    h.start();
    const m = await nextMessage(h, (m) => m.kind === 'control');
    expect(m).toMatchObject({ kind: 'control', json: { event: 'hello', version: 'fake' } });
  });

  it('reassembles a message written in pieces', async () => {
    const h = make(['--hello', '--split']);
    h.start();
    const m = await nextMessage(h, (m) => m.kind === 'control');
    expect((m as { json: { event: string } }).json.event).toBe('hello');
  });

  it('receives a frame message', async () => {
    const h = make(['--frame']);
    h.start();
    const m = await nextMessage(h, (m) => m.kind === 'frame');
    expect(m).toMatchObject({ kind: 'frame', width: 4, height: 2 });
  });

  it('sends commands to the helper as JSON lines', async () => {
    const h = make(['--echo']);
    h.start();
    h.send({ cmd: 'connect', uuid: 'abc' });
    const m = await nextMessage(
      h,
      (m) => m.kind === 'control' && (m.json as { event?: string }).event === 'echo'
    );
    expect(m).toMatchObject({
      kind: 'control',
      json: { event: 'echo', received: { cmd: 'connect', uuid: 'abc' } },
    });
  });

  it('restarts automatically after an abnormal exit', async () => {
    const h = make(['--hello', '--crash-after', '150'], { backoffMs: [50, 50, 50] });
    let helloCount = 0;
    h.on('message', (m: HelperMessage) => {
      if (m.kind === 'control' && (m.json as { event?: string }).event === 'hello') helloCount++;
    });
    h.start();
    await new Promise((r) => setTimeout(r, 900));
    expect(helloCount).toBeGreaterThanOrEqual(2);
  });

  it('gives up once the restart limit is reached', async () => {
    const h = make(['--crash-after', '30'], { maxRestarts: 2, backoffMs: [20, 20] });
    const gaveUp = new Promise<string>((resolve) => h.on('giveUp', resolve));
    h.start();
    const reason = await gaveUp;
    expect(reason).toContain('Gave up after');
    expect(h.running).toBe(false);
  });

  it('suggests clearing quarantine when dyld fails to load', async () => {
    const h = make(
      [
        '--stderr',
        'dyld[1]: Library not loaded: @rpath/Syphon.framework/Versions/A/Syphon',
        '--crash-after',
        '30',
      ],
      { maxRestarts: 1, backoffMs: [20] }
    );
    const gaveUp = new Promise<string>((resolve) => h.on('giveUp', resolve));
    h.start();
    const reason = await gaveUp;
    expect(reason).toContain('xattr -dr com.apple.quarantine');
  });

  it('omits the quarantine hint for an ordinary crash', async () => {
    const h = make(['--crash-after', '30'], { maxRestarts: 1, backoffMs: [20] });
    const gaveUp = new Promise<string>((resolve) => h.on('giveUp', resolve));
    h.start();
    const reason = await gaveUp;
    expect(reason).not.toContain('xattr');
  });

  it('does not restart after dispose', async () => {
    const h = make(['--hello', '--crash-after', '80'], { backoffMs: [30, 30, 30] });
    let helloCount = 0;
    h.on('message', (m: HelperMessage) => {
      if (m.kind === 'control') helloCount++;
    });
    h.start();
    await new Promise((r) => setTimeout(r, 150));
    h.dispose();
    const countAtDispose = helloCount;
    await new Promise((r) => setTimeout(r, 300));
    expect(helloCount).toBe(countAtDispose);
  });
});
