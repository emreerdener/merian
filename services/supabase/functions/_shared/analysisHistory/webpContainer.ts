/** Bounded still-container/header inspection, not entropy/pixel decoding or
 * metadata sanitization. The video policy retains its closed opaque-frame set.
 * https://developers.google.com/speed/webp/docs/riff_container */
export class WebpContainerRejected extends Error {}
const reject = (): never => {
  throw new WebpContainerRejected();
};
export interface WebpContainerLimits {
  maximumBytes: number;
  maximumWidth: number;
  maximumHeight: number;
  maximumPixels: number;
}
export function inspectWebpContainer(
  bytes: Uint8Array,
  limits: WebpContainerLimits,
  policy: "opaque_frame" | "private_still",
  checkpoint: () => void = () => {},
): { width: number; height: number } {
  for (
    const [key, ceiling] of [
      ["maximumBytes", 33_554_432],
      ["maximumWidth", 0x1000000],
      ["maximumHeight", 0x1000000],
      ["maximumPixels", 0xffffffff],
    ] as const
  ) {
    if (
      !Number.isSafeInteger(limits[key]) || limits[key] < 1 ||
      limits[key] > ceiling
    ) reject();
  }
  if (policy !== "opaque_frame" && policy !== "private_still") reject();
  if (bytes.length < 26 || bytes.length > limits.maximumBytes) reject();
  const strict = policy === "opaque_frame";
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const tag = (at: number) =>
    String.fromCharCode(...bytes.subarray(at, at + 4));
  const u24 = (at: number) =>
    bytes[at] + bytes[at + 1] * 256 + bytes[at + 2] * 65536;
  const size = (width: number, height: number) => {
    if (
      width < 1 || height < 1 || width > limits.maximumWidth ||
      height > limits.maximumHeight || width * height > limits.maximumPixels
    ) reject();
    return { width, height };
  };
  if (
    tag(0) !== "RIFF" || tag(8) !== "WEBP" ||
    view.getUint32(4, true) !== bytes.length - 8
  ) reject();
  let pos = 12, flags = 0;
  let canvas: { width: number; height: number } | undefined;
  let image: { width: number; height: number } | undefined;
  let alpha: { compression: number; length: number } | undefined;
  let lossless = false;
  const seen = new Set<string>();
  for (
    let count = 0;
    count < (strict ? 2 : 4096) && pos < bytes.length;
    count++
  ) {
    checkpoint();
    if (bytes.length - pos < 8) reject();
    const kind = tag(pos),
      length = view.getUint32(pos + 4, true),
      data = pos + 8;
    if (length > bytes.length - data) reject();
    const end = data + length, padded = end + length % 2;
    if (padded > bytes.length || (length % 2 && bytes[end] !== 0)) reject();
    if (
      ["VP8X", "VP8 ", "VP8L", "ICCP", "ALPH", "EXIF", "XMP "].includes(kind)
    ) {
      if (seen.has(kind)) reject();
      seen.add(kind);
    }
    if (kind === "VP8X") {
      if (
        pos !== 12 || length !== 10 || bytes[data + 1] || bytes[data + 2] ||
        bytes[data + 3]
      ) reject();
      flags = bytes[data];
      // Reserved bits and animation are not accepted by either still policy.
      if ((flags & 0xc3) || (strict && flags !== 0)) reject();
      canvas = size(u24(data + 4) + 1, u24(data + 7) + 1);
    } else if (kind === "VP8 ") {
      if (image || length < 11) reject();
      const header = u24(data), partition = header >>> 5;
      if (
        (header & 1) !== 0 || ((header >>> 1) & 7) > 3 || !(header & 16) ||
        partition === 0 || partition >= length - 10 ||
        bytes[data + 3] !== 0x9d ||
        bytes[data + 4] !== 1 || bytes[data + 5] !== 0x2a
      ) reject();
      const width = view.getUint16(data + 6, true),
        height = view.getUint16(data + 8, true);
      // Preserve the existing unscaled-keyframe policy; scaled VP8 is unqualified.
      if ((width & 0xc000) || (height & 0xc000)) reject();
      image = size(width, height);
    } else if (kind === "VP8L") {
      if (image || alpha || length < 6 || bytes[data] !== 0x2f) reject();
      const header = view.getUint32(data + 1, true);
      if ((header >>> (strict ? 28 : 29)) !== 0) reject();
      // Bit 28 is an informational alpha hint, not proof of decoded transparency.
      image = size((header & 0x3fff) + 1, ((header >>> 14) & 0x3fff) + 1);
      lossless = true;
    } else {
      if (strict || !canvas) reject();
      if (kind === "ANIM" || kind === "ANMF") reject();
      if (kind === "ICCP") {
        if (image || alpha || !(flags & 0x20) || length === 0) reject();
      } else if (kind === "ALPH") {
        if (image || !(flags & 0x10) || length < 2) reject();
        const header = bytes[data];
        if ((header & 0xc0) || ((header >>> 4) & 3) > 1 || (header & 3) > 1) {
          reject();
        }
        alpha = { compression: header & 3, length: length - 1 };
      } else if (kind === "EXIF" || kind === "XMP ") {
        if (!(flags & (kind === "EXIF" ? 8 : 4))) reject();
      } else if (!/^[\x20-\x7e]{4}$/.test(kind)) reject();
      // Metadata/unknown payloads remain opaque and may appear out of order.
    }
    pos = padded;
  }
  if (!image || pos !== bytes.length) return reject();
  if (canvas) {
    if (
      canvas.width !== image.width || canvas.height !== image.height ||
      Boolean(flags & 0x20) !== seen.has("ICCP") ||
      Boolean(flags & 8) !== seen.has("EXIF") ||
      Boolean(flags & 4) !== seen.has("XMP ") ||
      (!lossless && Boolean(flags & 0x10) !== Boolean(alpha))
    ) reject();
  }
  if (alpha?.compression === 0 && alpha.length !== image.width * image.height) {
    reject();
  }
  checkpoint();
  return image;
}
