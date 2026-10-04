export function joined(...parts: Uint8Array[]): Uint8Array {
  const result = new Uint8Array(parts.reduce((sum, p) => sum + p.length, 0));
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}
export function jpegSegment(marker: number, payload: number[]): Uint8Array {
  const length = payload.length + 2;
  return new Uint8Array([255, marker, length >> 8, length & 255, ...payload]);
}
export function safeJpeg(): Uint8Array {
  const counts = [1, ...Array(15).fill(0)];
  return joined(
    new Uint8Array([255, 216]),
    jpegSegment(0xdb, [0, ...Array(64).fill(1)]),
    jpegSegment(0xc0, [8, 0, 8, 0, 8, 1, 1, 0x11, 0]),
    jpegSegment(0xc4, [0, ...counts, 0, 16, ...counts, 0]),
    jpegSegment(0xda, [1, 1, 0, 0, 63, 0]),
    new Uint8Array([0x3f, 255, 217]),
  );
}
export function pngChunk(type: string, data: number[] = []): Uint8Array {
  const body = new Uint8Array([...new TextEncoder().encode(type), ...data]);
  let crc = 0xffffffff;
  for (const byte of body) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) {
      crc = crc & 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
    }
  }
  const result = new Uint8Array(body.length + 8),
    view = new DataView(result.buffer);
  view.setUint32(0, data.length);
  result.set(body, 4);
  view.setUint32(result.length - 4, (crc ^ 0xffffffff) >>> 0);
  return result;
}
export function pngParts(): Uint8Array[] {
  return [
    new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk("IHDR", [0, 0, 0, 1, 0, 0, 0, 1, 8, 0, 0, 0, 0]),
    pngChunk("IDAT", [120, 1, 1, 2, 0, 253, 255, 0, 128, 0, 130, 0, 129]),
    pngChunk("IEND"),
  ];
}
export const safePng = () => joined(...pngParts());
