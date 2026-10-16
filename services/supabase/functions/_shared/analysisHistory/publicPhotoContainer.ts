import {
  inspectJpegContainer,
  JpegContainerRejected,
} from "./jpegContainer.ts";
// This is a bounded metadata/container policy, not an image decoder. It never
// rewrites bytes: the public object must be the exact artifact that was approved.
const MAX_BYTES = 12 * 1024 * 1024;
const MAX_PIXELS = 40_000_000;
export const PUBLIC_PHOTO_CONTAINER_POLICY = "public_photo_container_v1";
/** Deliberate policy rejection only; unexpected validator failures are not proof. */
export class PublicPhotoContainerRejected extends Error {
  constructor() {
    super("publication_photo_not_sanitized");
    this.name = "PublicPhotoContainerRejected";
  }
}
function reject(): never {
  throw new PublicPhotoContainerRejected();
}
function dimensions(width: number, height: number) {
  if (
    width < 1 || height < 1 || width > 8192 || height > 8192 ||
    width * height > MAX_PIXELS
  ) reject();
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
  if (contentType === "image/jpeg") {
    try {
      inspectJpegContainer(bytes, (marker, payload, offset) => {
        const jfif = [74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0];
        if (
          marker !== 0xe0 || offset !== 2 || payload.length !== jfif.length ||
          !jfif.every((byte, index) => payload[index] === byte)
        ) reject();
      });
    } catch (error) {
      if (error instanceof JpegContainerRejected) reject();
      throw error;
    }
    return;
  }
  if (contentType === "image/png") return png(bytes);
  reject(); // HEIC and transformed derivatives require a separately reviewed path.
}
