// A stand-in helper for HelperProcess tests. Never touches Syphon.
// Behaviour is selected by argument:
//   --hello             send one hello on start
//   --echo              echo stdin commands back as control messages
//   --frame             send a single frame
//   --crash-after <ms>  exit abnormally after the given delay
//   --split             write hello one byte at a time
//   --stderr <text>     write one line to stderr on start

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const val = (f, d) => {
  const i = args.indexOf(f);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : d;
};

function encodeControl(obj) {
  const payload = Buffer.from(JSON.stringify(obj), 'utf8');
  const head = Buffer.alloc(5);
  head.writeUInt32BE(1 + payload.length, 0);
  head[4] = 0x01;
  return Buffer.concat([head, payload]);
}

function encodeFrame(width, height, jpeg) {
  const head = Buffer.alloc(13);
  head.writeUInt32BE(1 + 8 + jpeg.length, 0);
  head[4] = 0x02;
  head.writeUInt32BE(width, 5);
  head.writeUInt32BE(height, 9);
  return Buffer.concat([head, jpeg]);
}

const stderrText = val('--stderr', null);
if (stderrText !== null) {
  process.stderr.write(stderrText + '\n');
}

if (has('--hello')) {
  const bytes = encodeControl({ event: 'hello', version: 'fake', pid: process.pid });
  if (has('--split')) {
    for (const b of bytes) process.stdout.write(Buffer.from([b]));
  } else {
    process.stdout.write(bytes);
  }
}

if (has('--frame')) {
  process.stdout.write(encodeFrame(4, 2, Buffer.from([0xff, 0xd8, 0xff, 0xd9])));
}

if (has('--echo')) {
  let pending = '';
  process.stdin.on('data', (chunk) => {
    pending += chunk.toString('utf8');
    let nl;
    while ((nl = pending.indexOf('\n')) >= 0) {
      const line = pending.slice(0, nl);
      pending = pending.slice(nl + 1);
      if (!line) continue;
      process.stdout.write(encodeControl({ event: 'echo', received: JSON.parse(line) }));
    }
  });
}

const crashAfter = val('--crash-after', null);
if (crashAfter !== null) {
  setTimeout(() => process.exit(3), Number(crashAfter));
} else if (!has('--echo')) {
  // Exit when stdin closes
  process.stdin.resume();
  process.stdin.on('end', () => process.exit(0));
}
