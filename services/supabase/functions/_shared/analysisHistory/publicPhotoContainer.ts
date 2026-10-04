// This is a bounded metadata/container policy, not an image decoder. It never
// rewrites bytes: the public object must be the exact artifact that was approved.
const MAX_BYTES = 12 * 1024 * 1024;
const MAX_PIXELS = 40_000_000;
function reject(): never {
  throw new Error("publication_photo_not_sanitized");
}
function dimensions(width: number, height: number) {
  if (
    width < 1 || height < 1 || width > 8192 || height > 8192 ||
    width * height > MAX_PIXELS
  ) reject();
}
function jpeg(bytes: Uint8Array) {
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8) reject();
  let pos = 2, frame = 0, scans = 0, restart = 0;
  const components = new Map<number, number>();
  const quantization = new Set<number>(), huffman = new Set<number>();
  const u16 = (i: number) => bytes[i] * 256 + bytes[i + 1];
  for (let markers = 0; markers < 4096 && pos < bytes.length; markers++) {
    const start = pos;
    if (bytes[pos++] !== 0xff) reject();
    while (bytes[pos] === 0xff) pos++;
    const marker = bytes[pos++];
    if (marker === 0xd9) {
      if (!frame || !scans || pos !== bytes.length) reject();
      return;
    }
    if (
      ![0xe0, 0xc0, 0xc2, 0xc4, 0xdb, 0xdd, 0xda].includes(marker) ||
      pos + 2 > bytes.length
    ) reject();
    const length = u16(pos), data = pos + 2, end = pos + length;
    if (length < 2 || end > bytes.length) reject();
    if (marker === 0xe0) {
      // Exactly the minimal JFIF 1.1 format header: no thumbnail, density,
      // extension bytes or arbitrary strings. Every other APP/COM is rejected.
      const jfif = [74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0];
      if (
        start !== 2 || length !== 16 ||
        !jfif.every((b, i) => bytes[data + i] === b)
      ) reject();
    } else if (marker === 0xc0 || marker === 0xc2) {
      if (frame || length < 11 || bytes[data] !== 8) reject();
      dimensions(u16(data + 3), u16(data + 1));
      const count = bytes[data + 5];
      if (count < 1 || count > 4 || length !== 8 + count * 3) reject();
      for (let n = 0; n < count; n++) {
        const at = data + 6 + n * 3,
          id = bytes[at],
          sampling = bytes[at + 1],
          table = bytes[at + 2];
        if (
          components.has(id) || (sampling >> 4) < 1 || (sampling >> 4) > 4 ||
          (sampling & 15) < 1 || (sampling & 15) > 4 || table > 3
        ) reject();
        components.set(id, table);
      }
      frame = marker;
    } else if (marker === 0xdb) {
      let at = data;
      while (at < end) {
        const spec = bytes[at++], precision = spec >> 4, id = spec & 15;
        if (precision > 1 || id > 3 || at + 64 * (precision + 1) > end) {
          reject();
        }
        for (let n = 0; n < 64; n++, at += precision + 1) {
          if ((precision ? u16(at) : bytes[at]) === 0) reject();
        }
        quantization.add(id);
      }
      if (at !== end || at === data) reject();
    } else if (marker === 0xc4) {
      let at = data;
      while (at < end) {
        const spec = bytes[at++];
        if ((spec >> 4) > 1 || (spec & 15) > 3 || at + 16 > end) reject();
        let count = 0, available = 1;
        for (let n = 0; n < 16; n++) {
          const symbols = bytes[at++];
          available = available * 2 - symbols;
          if (available < 0) reject();
          count += symbols;
        }
        if (count < 1 || count > 256 || at + count > end) reject();
        at += count;
        huffman.add(spec);
      }
      if (at !== end || at === data) reject();
    } else if (marker === 0xdd) {
      if (length !== 4) reject();
      restart = u16(data);
    } else {
      if (!frame || ++scans > 64 || length < 8) reject();
      const count = bytes[data], selected = new Set<number>();
      if (count < 1 || count > components.size || length !== 6 + count * 2) {
        reject();
      }
      const spectral = data + 1 + count * 2;
      const first = bytes[spectral],
        last = bytes[spectral + 1],
        approximation = bytes[spectral + 2];
      if (
        first > last || last > 63 || (approximation >> 4) > 13 ||
        (approximation & 15) > 13 ||
        (frame === 0xc0 &&
          (first !== 0 || last !== 63 || approximation !== 0)) ||
        (frame === 0xc2 &&
          ((first === 0 && last !== 0) || (first > 0 && count !== 1)))
      ) reject();
      for (let n = 0; n < count; n++) {
        const id = bytes[data + 1 + n * 2], tables = bytes[data + 2 + n * 2];
        if (
          !components.has(id) || selected.has(id) ||
          !quantization.has(components.get(id)!) ||
          (tables >> 4) > 3 || (tables & 15) > 3 ||
          (first === 0 && !huffman.has(tables >> 4)) ||
          (last > 0 && !huffman.has(16 | (tables & 15)))
        ) reject();
        selected.add(id);
      }
      let at = end, entropy = 0, expectedRestart = 0;
      for (; at < bytes.length;) {
        if (bytes[at] !== 0xff) {
          at++;
          entropy++;
          continue;
        }
        const markerStart = at++;
        while (bytes[at] === 0xff) at++;
        const code = bytes[at];
        if (code === 0) {
          if (at !== markerStart + 1) reject();
          at++;
          entropy++;
          continue;
        }
        if (code >= 0xd0 && code <= 0xd7) {
          if (!restart || code !== 0xd0 + expectedRestart) reject();
          expectedRestart = (expectedRestart + 1) % 8;
          at++;
          continue;
        }
        if (!entropy) reject();
        pos = markerStart;
        break;
      }
      if (at >= bytes.length) reject();
      continue;
    }
    pos = end;
  }
  reject();
}
const crcTable = Uint32Array.from({ length: 256 }, (_, value) => {
  for (let n = 0; n < 8; n++) {
    value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
  }
  return value >>> 0;
});
function png(bytes: Uint8Array) {
  if (![137, 80, 78, 71, 13, 10, 26, 10].every((b, i) => bytes[i] === b)) {
    reject();
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const seen = new Set<string>();
  let pos = 8,
    color = -1,
    depth = 0,
    palette = 0,
    dataBytes = 0,
    dataEnded = false;
  const zlib: number[] = [];
  for (let chunks = 0; chunks < 4096 && pos + 12 <= bytes.length; chunks++) {
    const length = view.getUint32(pos), data = pos + 8, end = data + length;
    if (end + 4 > bytes.length) reject();
    const type = String.fromCharCode(...bytes.subarray(pos + 4, pos + 8));
    if (
      !["IHDR", "PLTE", "tRNS", "gAMA", "cHRM", "sRGB", "IDAT", "IEND"]
        .includes(type) ||
      (type !== "IDAT" && seen.has(type)) || (chunks === 0 && type !== "IHDR")
    ) reject();
    let crc = 0xffffffff;
    for (let at = pos + 4; at < end; at++) {
      crc = crcTable[(crc ^ bytes[at]) & 255] ^ (crc >>> 8);
    }
    if (((crc ^ 0xffffffff) >>> 0) !== view.getUint32(end)) reject();
    if (seen.has("IDAT") && type !== "IDAT") dataEnded = true;
    if (type === "IHDR") {
      if (length !== 13) reject();
      dimensions(view.getUint32(data), view.getUint32(data + 4));
      depth = bytes[data + 8];
      color = bytes[data + 9];
      const depths: Record<number, number[]> = {
        0: [1, 2, 4, 8, 16],
        2: [8, 16],
        3: [1, 2, 4, 8],
        4: [8, 16],
        6: [8, 16],
      };
      if (
        !depths[color]?.includes(depth) || bytes[data + 10] !== 0 ||
        bytes[data + 11] !== 0 || bytes[data + 12] > 1
      ) reject();
    } else if (type === "PLTE") {
      if (
        seen.has("IDAT") || seen.has("tRNS") || [0, 4].includes(color) ||
        !length || length % 3 || length > 768
      ) reject();
      palette = length / 3;
      if (color === 3 && palette > 2 ** depth) reject();
    } else if (type === "tRNS") {
      if (
        seen.has("IDAT") ||
        (color === 0
          ? length !== 2
          : color === 2
          ? length !== 6
          : color === 3
          ? !palette || length < 1 || length > palette
          : true)
      ) reject();
    } else if (["gAMA", "cHRM", "sRGB"].includes(type)) {
      if (seen.has("PLTE") || seen.has("IDAT")) reject();
      if (type === "gAMA" && (length !== 4 || view.getUint32(data) === 0)) {
        reject();
      }
      if (type === "cHRM" && length !== 32) reject();
      if (type === "sRGB" && (length !== 1 || bytes[data] > 3)) reject();
    } else if (type === "IDAT") {
      if (dataEnded || (color === 3 && !palette)) reject();
      dataBytes += length;
      for (let at = data; at < end && zlib.length < 2; at++) {
        zlib.push(bytes[at]);
      }
    } else if (type === "IEND") {
      if (
        length || end + 4 !== bytes.length || dataBytes < 6 ||
        zlib.length !== 2 ||
        (zlib[0] & 15) !== 8 || (zlib[0] >> 4) > 7 || (zlib[1] & 32) ||
        (zlib[0] * 256 + zlib[1]) % 31
      ) reject();
      return;
    }
    seen.add(type);
    pos = end + 4;
  }
  reject();
}
export function validatePublicPhotoContainer(
  bytes: Uint8Array,
  contentType: string,
): void {
  if (bytes.byteLength < 4 || bytes.byteLength > MAX_BYTES) reject();
  if (contentType === "image/jpeg") return jpeg(bytes);
  if (contentType === "image/png") return png(bytes);
  reject(); // HEIC and transformed derivatives require a separately reviewed path.
}
