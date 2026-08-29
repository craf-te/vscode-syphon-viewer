import { describe, it, expect } from 'vitest';
import { MessageDecoder, ProtocolError, MAX_MESSAGE_SIZE } from '../src/protocol';

// The byte layout is written out by hand here. Reusing the production encoder
// would only prove the decoder agrees with it, not with the specification.
function encodeControl(obj: unknown): Uint8Array {
  const payload = new TextEncoder().encode(JSON.stringify(obj));
  const out = new Uint8Array(4 + 1 + payload.length);
  new DataView(out.buffer).setUint32(0, 1 + payload.length, false);
  out[4] = 0x01;
  out.set(payload, 5);
  return out;
}

function encodeFrame(width: number, height: number, pixels: Uint8Array): Uint8Array {
  const out = new Uint8Array(4 + 1 + 4 + 4 + pixels.length);
  const view = new DataView(out.buffer);
  view.setUint32(0, 1 + 8 + pixels.length, false);
  out[4] = 0x02;
  view.setUint32(5, width, false);
  view.setUint32(9, height, false);
  out.set(pixels, 13);
  return out;
}

function rawHeader(len: number, type: number): Uint8Array {
  const out = new Uint8Array(5);
  new DataView(out.buffer).setUint32(0, len, false);
  out[4] = type;
  return out;
}

describe('MessageDecoder', () => {
  it('decodes a control message from one chunk', () => {
    const d = new MessageDecoder();
    const msgs = d.push(encodeControl({ event: 'hello', pid: 42 }));
    expect(msgs).toHaveLength(1);
    expect(msgs[0]).toEqual({ kind: 'control', json: { event: 'hello', pid: 42 } });
  });

  it('extracts width, height and pixels from a frame', () => {
    const d = new MessageDecoder();
    // 2x1 RGBA: red on the left, blue on the right.
    const pixels = new Uint8Array([255, 0, 0, 255, 0, 0, 255, 255]);
    const msgs = d.push(encodeFrame(2, 1, pixels));
    expect(msgs).toHaveLength(1);
    expect(msgs[0]).toEqual({ kind: 'frame', width: 2, height: 1, pixels });
  });

  it('reassembles a message split across chunks', () => {
    const d = new MessageDecoder();
    const bytes = encodeControl({ event: 'servers', servers: [] });
    expect(d.push(bytes.slice(0, 3))).toHaveLength(0);
    expect(d.push(bytes.slice(3, 9))).toHaveLength(0);
    const msgs = d.push(bytes.slice(9));
    expect(msgs).toHaveLength(1);
    expect(msgs[0]).toEqual({ kind: 'control', json: { event: 'servers', servers: [] } });
  });

  it('handles a chunk boundary inside the length prefix', () => {
    const d = new MessageDecoder();
    const bytes = encodeControl({ a: 1 });
    expect(d.push(bytes.slice(0, 2))).toHaveLength(0);
    const msgs = d.push(bytes.slice(2));
    expect(msgs).toHaveLength(1);
  });

  it('returns every message packed into one chunk', () => {
    const d = new MessageDecoder();
    const a = encodeControl({ event: 'connected' });
    const b = encodeFrame(2, 2, new Uint8Array([1, 2, 3]));
    const c = encodeControl({ event: 'stats', fps: 30 });
    const merged = new Uint8Array(a.length + b.length + c.length);
    merged.set(a, 0);
    merged.set(b, a.length);
    merged.set(c, a.length + b.length);

    const msgs = d.push(merged);
    expect(msgs).toHaveLength(3);
    expect(msgs[0].kind).toBe('control');
    expect(msgs[1].kind).toBe('frame');
    expect(msgs[2].kind).toBe('control');
  });

  it('rejects a zero length', () => {
    const d = new MessageDecoder();
    expect(() => d.push(rawHeader(0, 0x01))).toThrow(ProtocolError);
  });

  it('rejects a length past the limit', () => {
    const d = new MessageDecoder();
    expect(() => d.push(rawHeader(MAX_MESSAGE_SIZE + 1, 0x01))).toThrow(ProtocolError);
  });

  it('rejects an unknown message type', () => {
    const d = new MessageDecoder();
    const bad = new Uint8Array(6);
    new DataView(bad.buffer).setUint32(0, 2, false);
    bad[4] = 0x09;
    bad[5] = 0x00;
    expect(() => d.push(bad)).toThrow(ProtocolError);
  });

  it('rejects a frame payload shorter than 8 bytes', () => {
    const d = new MessageDecoder();
    const bad = new Uint8Array(4 + 1 + 4);
    const view = new DataView(bad.buffer);
    view.setUint32(0, 1 + 4, false);
    bad[4] = 0x02;
    view.setUint32(5, 100, false);
    expect(() => d.push(bad)).toThrow(ProtocolError);
  });

  it('returns pixels independent of the source buffer', () => {
    const d = new MessageDecoder();
    const pixels = new Uint8Array([9, 8, 7, 255]);
    const bytes = encodeFrame(1, 1, pixels);
    const msgs = d.push(bytes);
    bytes.fill(0);
    expect(msgs[0]).toMatchObject({ kind: 'frame', pixels: new Uint8Array([9, 8, 7, 255]) });
  });

  it('assembles a raw 1080p frame from 64KB fragments in reasonable time', () => {
    // A raw frame is 8.29MB and arrives as 64KB pipe fragments. Concatenating
    // the whole buffer per chunk is O(n^2) and measured 61ms per frame, which
    // alone breaks a 30fps feed.
    const W = 1920, H = 1080;
    const pixels = new Uint8Array(W * H * 4);
    const bytes = encodeFrame(W, H, pixels);

    const d = new MessageDecoder();
    const CHUNK = 65536;
    const started = Date.now();
    let msgs: ReturnType<MessageDecoder['push']> = [];
    for (let off = 0; off < bytes.length; off += CHUNK) {
      msgs = msgs.concat(d.push(bytes.subarray(off, Math.min(off + CHUNK, bytes.length))));
    }
    const elapsed = Date.now() - started;

    expect(msgs).toHaveLength(1);
    expect(msgs[0]).toMatchObject({ kind: 'frame', width: W, height: H });
    expect((msgs[0] as { pixels: Uint8Array }).pixels.length).toBe(W * H * 4);
    // The 30fps budget is 33ms per frame; assembly must not eat all of it.
    expect(elapsed).toBeLessThan(15);
  });

  it('accepts a raw 4K frame (33.2MB) as within the limit', () => {
    const d = new MessageDecoder();
    const bytes = new Uint8Array(5);
    new DataView(bytes.buffer).setUint32(0, 1 + 8 + 3840 * 2160 * 4, false);
    bytes[4] = 0x02;
    // Must not throw for being too long; nothing is returned because the body
    // has not arrived yet.
    expect(d.push(bytes)).toHaveLength(0);
  });
});
