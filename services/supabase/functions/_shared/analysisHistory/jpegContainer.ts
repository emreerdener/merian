// Bounded JPEG marker/table/scan structure, not pixel decoding or sanitization.
// Each caller owns its metadata policy. Entropy is framed, not decoded.
export class JpegContainerRejected extends Error {}
function reject(): never {
  throw new JpegContainerRejected();
}
export function inspectJpegContainer(
  bytes: Uint8Array,
  metadata: (
    marker: number,
    payload: Uint8Array,
    offset: number,
    hasFrame: boolean,
  ) => void,
): { width: number; height: number } {
  if (bytes.length < 4 || bytes.length > 12 * 1024 * 1024) reject();
  let width = 0, height = 0;
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
      return { width, height };
    }
    const isMetadata = marker >= 0xe0 && marker <= 0xef || marker === 0xfe;
    if (
      (!isMetadata && ![0xc0, 0xc2, 0xc4, 0xdb, 0xdd, 0xda].includes(marker)) ||
      pos + 2 > bytes.length
    ) reject();
    const length = u16(pos), data = pos + 2, end = pos + length;
    if (length < 2 || end > bytes.length) reject();
    if (isMetadata) {
      metadata(marker, bytes.subarray(data, end), start, frame !== 0);
    } else if (marker === 0xc0 || marker === 0xc2) {
      if (frame || length < 11 || bytes[data] !== 8) reject();
      width = u16(data + 3);
      height = u16(data + 1);
      if (
        width < 1 || height < 1 || width > 8192 || height > 8192 ||
        width * height > 40_000_000
      ) reject();
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
