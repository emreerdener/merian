// Shared PNG chunk/CRC/critical ordering and zlib-header framing, not pixel or
// deflate decoding. Unknown critical chunks fail; consumers own ancillary policy.
// W3C PNG Third Edition sections5/10/11: https://www.w3.org/TR/png-3/
export class PngContainerRejected extends Error {}
function reject(): never {
  throw new PngContainerRejected();
}
export interface PngContainerLimits {
  maximumBytes: number;
  maximumWidth: number;
  maximumHeight: number;
  maximumPixels: number;
}
const crcTable = Uint32Array.from({ length: 256 }, (_, value) => {
  for (let n = 0; n < 8; n++) {
    value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
  }
  return value >>> 0;
});
export function inspectPngContainer(
  bytes: Uint8Array,
  limits: Readonly<PngContainerLimits>,
  ancillary: (type: string, payload: Uint8Array, beforeData: boolean) => void =
    () => reject(),
): { width: number; height: number } {
  const { maximumBytes, maximumWidth, maximumHeight, maximumPixels } = limits;
  if (
    [maximumBytes, maximumWidth, maximumHeight, maximumPixels].some((n) =>
      !Number.isSafeInteger(n) || n < 1
    ) ||
    maximumBytes > 33_554_432 || maximumWidth > 0x7fffffff ||
    maximumHeight > 0x7fffffff ||
    bytes.length < 8 || bytes.length > maximumBytes
  ) reject();
  let width = 0, height = 0;
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
    const core = [
      "IHDR",
      "PLTE",
      "tRNS",
      "gAMA",
      "cHRM",
      "sRGB",
      "IDAT",
      "IEND",
    ].includes(type);
    if (
      !/^[A-Za-z]{2}[A-Z][A-Za-z]$/.test(type) ||
      (!core && !(bytes[pos + 4] & 32)) ||
      (core && type !== "IDAT" && seen.has(type)) ||
      (chunks === 0 && type !== "IHDR")
    ) reject();
    let crc = 0xffffffff;
    for (let at = pos + 4; at < end; at++) {
      crc = crcTable[(crc ^ bytes[at]) & 255] ^ (crc >>> 8);
    }
    if (((crc ^ 0xffffffff) >>> 0) !== view.getUint32(end)) reject();
    if (seen.has("IDAT") && type !== "IDAT") dataEnded = true;
    if (type === "IHDR") {
      if (length !== 13) reject();
      width = view.getUint32(data);
      height = view.getUint32(data + 4);
      if (
        width < 1 || height < 1 || width > maximumWidth ||
        height > maximumHeight ||
        !Number.isSafeInteger(width * height) || width * height > maximumPixels
      ) reject();
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
      return { width, height };
    } else {
      ancillary(type, bytes.subarray(data, end), !seen.has("IDAT"));
    }
    seen.add(type);
    pos = end + 4;
  }
  reject();
}
