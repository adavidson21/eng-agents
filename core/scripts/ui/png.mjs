// Tiny PNG reader, writer and pixel diff for UI checks. No dependencies: node:zlib only.
// Reads 8-bit, non-interlaced PNGs in truecolor (2), truecolor with alpha (6), grey (0) or grey with alpha (4),
// which is what browsers write for screenshots. Anything else throws.

import zlib from "node:zlib";

const SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const CHANNELS = { 0: 1, 2: 3, 4: 2, 6: 4 };

/** Decodes a PNG buffer to { width, height, data } with data as RGBA bytes. */
export function decodePng(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 8 || !buf.subarray(0, 8).equals(SIG)) throw new Error("not a PNG");
  let pos = 8;
  let width = 0, height = 0, depth = 0, color = 0, interlace = 0;
  const idat = [];
  while (pos + 8 <= buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString("latin1", pos + 4, pos + 8);
    const body = buf.subarray(pos + 8, pos + 8 + len);
    if (type === "IHDR") {
      width = body.readUInt32BE(0);
      height = body.readUInt32BE(4);
      depth = body[8];
      color = body[9];
      interlace = body[12];
    } else if (type === "IDAT") idat.push(body);
    else if (type === "IEND") break;
    pos += 12 + len;
  }
  if (depth !== 8 || interlace !== 0 || !CHANNELS[color]) throw new Error(`unsupported PNG (depth ${depth}, color ${color}, interlace ${interlace})`);
  const ch = CHANNELS[color];
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * ch;
  const out = Buffer.alloc(width * height * 4);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const f = raw[y * (stride + 1)];
    const line = Buffer.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let x = 0; x < stride; x++) {
      const a = x >= ch ? line[x - ch] : 0;
      const b = prev[x];
      const c = x >= ch ? prev[x - ch] : 0;
      let v = line[x];
      if (f === 1) v += a;
      else if (f === 2) v += b;
      else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) {
        const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      } else if (f !== 0) throw new Error(`bad PNG filter ${f}`);
      line[x] = v & 0xff;
    }
    for (let x = 0; x < width; x++) {
      const o = (y * width + x) * 4, i = x * ch;
      if (ch === 1 || ch === 2) { out[o] = out[o + 1] = out[o + 2] = line[i]; out[o + 3] = ch === 2 ? line[i + 1] : 255; }
      else { out[o] = line[i]; out[o + 1] = line[i + 1]; out[o + 2] = line[i + 2]; out[o + 3] = ch === 4 ? line[i + 3] : 255; }
    }
    prev = line;
  }
  return { width, height, data: out };
}

const CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(b) {
  let c = 0xffffffff;
  for (const x of b) c = CRC[(c ^ x) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, body) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(body.length);
  const tb = Buffer.concat([Buffer.from(type, "latin1"), body]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(tb));
  return Buffer.concat([len, tb, crc]);
}

/** Encodes { width, height, data (RGBA) } as a PNG buffer. */
export function encodePng({ width, height, data }) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) data.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  return Buffer.concat([SIG, chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

/**
 * Compares two decoded images. A pixel counts as changed when any channel differs by more than `threshold`.
 * Returns { changedPct, sizeChanged, image } where image marks changed pixels red over a faded copy of `after`.
 */
export function diffImages(before, after, threshold = 24) {
  if (before.width !== after.width || before.height !== after.height) return { changedPct: 100, sizeChanged: true, image: null };
  const { width, height } = after;
  const img = Buffer.alloc(width * height * 4);
  let changed = 0;
  for (let i = 0; i < width * height * 4; i += 4) {
    const d = Math.max(Math.abs(before.data[i] - after.data[i]), Math.abs(before.data[i + 1] - after.data[i + 1]), Math.abs(before.data[i + 2] - after.data[i + 2]));
    if (d > threshold) {
      changed++;
      img[i] = 230; img[i + 1] = 30; img[i + 2] = 40; img[i + 3] = 255;
    } else {
      const g = Math.round((after.data[i] + after.data[i + 1] + after.data[i + 2]) / 3);
      img[i] = img[i + 1] = img[i + 2] = 200 + Math.round(g / 5); img[i + 3] = 255;
    }
  }
  const pct = width * height ? Math.round((changed / (width * height)) * 10000) / 100 : 0;
  return { changedPct: pct, sizeChanged: false, image: { width, height, data: img } };
}
