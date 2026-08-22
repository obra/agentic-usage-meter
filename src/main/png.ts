// Minimal PNG encoder + tray gauge renderer (no native deps).

import { deflateSync } from "node:zlib";

function crc32(buffer: Buffer): number {
  let table = (crc32 as unknown as { table?: Int32Array }).table;
  if (!table) {
    table = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) {
        c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      }
      table[n] = c;
    }
    (crc32 as unknown as { table?: Int32Array }).table = table;
  }
  let crc = -1;
  for (const byte of buffer) {
    crc = (crc >>> 8) ^ table[(crc ^ byte) & 0xff]!;
  }
  return (crc ^ -1) >>> 0;
}

function chunk(type: string, data: Buffer): Buffer {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

export function encodePNG(
  width: number,
  height: number,
  rgba: (x: number, y: number) => [number, number, number, number],
): Buffer {
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    const rowStart = y * (width * 4 + 1);
    raw[rowStart] = 0; // filter: none
    for (let x = 0; x < width; x++) {
      const [r, g, b, a] = rgba(x, y);
      const offset = rowStart + 1 + x * 4;
      raw[offset] = r;
      raw[offset + 1] = g;
      raw[offset + 2] = b;
      raw[offset + 3] = a;
    }
  }
  const header = Buffer.alloc(8);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(header);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type RGBA
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  return Buffer.concat([
    header,
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

export interface GaugeColor {
  r: number;
  g: number;
  b: number;
}

function colorForFraction(fraction: number): GaugeColor {
  // green (remaining) → orange → red, matching the macOS tint semantics.
  if (fraction > 0.5) return { r: 52, g: 199, b: 89 };
  if (fraction > 0.2) return { r: 255, g: 159, b: 10 };
  return { r: 255, g: 69, b: 58 };
}

// A ring gauge: filled arc = remaining fraction, on a faint track. The dot
// in the middle distinguishes "no data" (hollow ring, gray) from data.
export function gaugeIconPNG(fraction: number | null, size: number): Buffer {
  const scale = 2; // supersample for smoother edges
  const dimension = size * scale;
  const center = dimension / 2;
  const radius = dimension / 2 - scale; // 1px margin at final size
  const stroke = Math.max(2 * scale, Math.round(dimension * 0.14));
  const color = fraction === null ? { r: 142, g: 142, b: 147 } : colorForFraction(fraction);

  const angleFor = (x: number, y: number): number => {
    // 0 = 12 o'clock, increases clockwise.
    const dx = x - center;
    const dy = y - center;
    let angle = Math.atan2(dx, -dy);
    if (angle < 0) angle += Math.PI * 2;
    return angle;
  };

  const png = encodePNG(dimension, dimension, (x, y) => {
    const dx = x + 0.5 - center;
    const dy = y + 0.5 - center;
    const distance = Math.sqrt(dx * dx + dy * dy);
    const outer = radius;
    const inner = radius - stroke;
    if (distance > outer + 0.5 || distance < inner - 0.5) return [0, 0, 0, 0];

    const angle = angleFor(x + 0.5, y + 0.5);
    const progress = angle / (Math.PI * 2);
    const filled = fraction !== null && progress <= fraction;

    let rgb: GaugeColor;
    let alpha: number;
    if (filled) {
      rgb = color;
      alpha = 255;
    } else {
      // track
      rgb = fraction === null ? { r: 142, g: 142, b: 147 } : color;
      alpha = fraction === null ? 110 : 70;
    }
    // 1px antialias at ring edges
    if (distance > outer - 0.5 || distance < inner + 0.5) {
      alpha = Math.round(alpha * 0.6);
    }
    return [rgb.r, rgb.g, rgb.b, alpha];
  });
  return png;
}

// App icon: rounded-square-style gauge on a dark background, sized for
// electron-builder conversion (ico/dmg).
export function appIconPNG(size: number): Buffer {
  const dimension = size;
  const center = dimension / 2;
  const radius = dimension * 0.31;
  const stroke = dimension * 0.085;
  const fraction = 0.72;
  const background = { r: 30, g: 30, b: 34 };
  const gauge = { r: 255, g: 122, b: 46 }; // Claude-ish orange accent
  const cornerRadius = dimension * 0.22;

  const inRoundedRect = (x: number, y: number): boolean => {
    const qx = Math.abs(x - center) - (center - cornerRadius);
    const qy = Math.abs(y - center) - (center - cornerRadius);
    const ax = Math.max(qx, 0);
    const ay = Math.max(qy, 0);
    const outside = Math.sqrt(ax * ax + ay * ay);
    const inside = Math.min(Math.max(qx, qy), 0);
    return outside + inside <= cornerRadius;
  };

  return encodePNG(dimension, dimension, (x, y) => {
    if (!inRoundedRect(x + 0.5, y + 0.5)) return [0, 0, 0, 0];
    const dx = x + 0.5 - center;
    const dy = y + 0.5 - center;
    const distance = Math.sqrt(dx * dx + dy * dy);
    if (distance > radius || distance < radius - stroke) {
      return [background.r, background.g, background.b, 255];
    }
    let angle = Math.atan2(dx, -dy);
    if (angle < 0) angle += Math.PI * 2;
    const filled = angle / (Math.PI * 2) <= fraction;
    return filled
      ? [gauge.r, gauge.g, gauge.b, 255]
      : [gauge.r, gauge.g, gauge.b, 90];
  });
}
