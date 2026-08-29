/** Decoder for the stdout protocol. Pure logic, no external dependencies. */

/**
 * Upper bound for one message; anything longer is treated as corrupt.
 * Raw RGBA at 4K (3840x2160) is 33.2MB, so this leaves some headroom above it.
 */
export const MAX_MESSAGE_SIZE = 67108864; // 64 MiB

const TYPE_CONTROL = 0x01;
const TYPE_FRAME = 0x02;
const HEADER_SIZE = 5; // len(4) + type(1)

export type HelperMessage =
  | { kind: 'control'; json: unknown }
  | { kind: 'frame'; width: number; height: number; pixels: Uint8Array };

/** A protocol violation. Callers should stop and restart the helper. */
export class ProtocolError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ProtocolError';
  }
}

/**
 * Buffers incoming chunks and hands back completed messages.
 *
 * Chunks are pushed onto an array rather than concatenated. A raw 1080p frame
 * is 8.29MB and arrives as roughly 130 fragments of 64KB. Concatenating the
 * whole buffer per chunk is an O(n^2) memcpy that measured 61ms per frame,
 * more than the entire 33ms budget of a 30fps feed on its own. Instead the
 * bytes are copied once, when a message is complete.
 */
export class MessageDecoder {
  private chunks: Uint8Array[] = [];
  private buffered = 0;

  push(chunk: Uint8Array): HelperMessage[] {
    if (chunk.length > 0) {
      this.chunks.push(chunk);
      this.buffered += chunk.length;
    }

    const messages: HelperMessage[] = [];
    for (;;) {
      if (this.buffered < HEADER_SIZE) break;

      const header = this.peek(HEADER_SIZE);
      const len = new DataView(header.buffer, header.byteOffset, header.length).getUint32(0, false);

      if (len === 0) {
        throw new ProtocolError('received a zero-length message');
      }
      if (len > MAX_MESSAGE_SIZE) {
        throw new ProtocolError(`message length exceeds the limit: ${len}`);
      }
      if (this.buffered < 4 + len) break; // not fully arrived yet

      const message = this.take(4 + len);
      messages.push(decodePayload(message[4], message.subarray(HEADER_SIZE)));
    }
    return messages;
  }

  /** Peeks at the first n bytes without consuming them. */
  private peek(n: number): Uint8Array {
    const first = this.chunks[0];
    if (first.length >= n) return first.subarray(0, n);

    const out = new Uint8Array(n);
    let filled = 0;
    for (const c of this.chunks) {
      const take = Math.min(n - filled, c.length);
      out.set(c.subarray(0, take), filled);
      filled += take;
      if (filled === n) break;
    }
    return out;
  }

  /** Consumes the first n bytes in a single copy, keeping the remainder. */
  private take(n: number): Uint8Array {
    const out = new Uint8Array(n);
    let filled = 0;
    let consumed = 0;

    for (const c of this.chunks) {
      if (filled === n) break;
      const take = Math.min(n - filled, c.length);
      out.set(c.subarray(0, take), filled);
      filled += take;
      if (take === c.length) {
        consumed += 1;
      } else {
        // Replace a partially consumed chunk with what is left of it
        this.chunks[consumed] = c.subarray(take);
        break;
      }
    }

    if (consumed > 0) this.chunks.splice(0, consumed);
    this.buffered -= n;
    return out;
  }
}

function decodePayload(type: number, payload: Uint8Array): HelperMessage {
  if (type === TYPE_CONTROL) {
    return { kind: 'control', json: JSON.parse(new TextDecoder().decode(payload)) };
  }
  if (type === TYPE_FRAME) {
    if (payload.length < 8) {
      throw new ProtocolError('frame payload is shorter than 8 bytes');
    }
    const view = new DataView(payload.buffer, payload.byteOffset, payload.length);
    return {
      kind: 'frame',
      width: view.getUint32(0, false),
      height: view.getUint32(4, false),
      // A view over the buffer take() just allocated, so no extra copy.
      pixels: payload.subarray(8),
    };
  }
  throw new ProtocolError(`unknown message type: 0x${type.toString(16)}`);
}
