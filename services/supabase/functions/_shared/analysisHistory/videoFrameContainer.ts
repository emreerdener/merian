import { invalidHistory } from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import {
  inspectJpegContainer,
  JpegContainerRejected,
} from "./jpegContainer.ts";
import { parsePreparedVideoManifest } from "./videoManifest.ts";

/** Private container policy only. No pixel decoding, derivation proof or admission.
 * JPEG permits only dimension-only ImageIO EXIF and the exact empty IPTC header;
 * WebP permits opaque still-image bitstreams without metadata or animation.
 */
export async function verifyPreparedVideoFrame(
  value: unknown,
  observationID: string,
  analysisID: string,
  index: number,
  input: Uint8Array,
): Promise<Uint8Array> {
  const manifest = parsePreparedVideoManifest(value, observationID, analysisID);
  if (!Number.isInteger(index) || index < 0 || index > 4) {
    return invalidHistory();
  }
  const artifact = manifest.provenance.frames[index].artifact;
  if (input.length !== artifact.byte_count) return invalidHistory();
  const bytes = input.slice(); // Manifest bounds the allocation before hashing awaits.
  const edge = manifest.provenance.parameters.inference_long_edge;
  if (artifact.content_type === "image/jpeg") jpeg(bytes, edge);
  else webp(bytes, edge);
  if (await evidenceDigest(bytes) !== artifact.sha256) return invalidHistory();
  return bytes;
}

const emptyIptc = hex(
  "50686f746f73686f7020332e30003842494d04040000000000003842494d0425000000000010d41d8cd98f00b204e9800998ecf8427e",
);
function hex(value: string): Uint8Array {
  return Uint8Array.from(
    value.match(/../g) ?? [],
    (pair) => parseInt(pair, 16),
  );
}
function equal(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((byte, index) => byte === b[index]);
}
function jpeg(bytes: Uint8Array, edge: number) {
  const seen = new Set<number>();
  const exif = hex(
    "4578696600004d4d002a00000008000187690004000000010000001a000000000002a00200040000000100000000a0030004000000010000000000000000",
  );
  // Exact big-endian dimension-only IFD emitted by the prepared ImageIO producer.
  const view = new DataView(exif.buffer);
  view.setUint32(42, edge);
  view.setUint32(54, edge);
  try {
    const size = inspectJpegContainer(
      bytes,
      (marker, payload, offset, hasFrame) => {
        if (hasFrame || seen.has(marker)) return invalidHistory();
        seen.add(marker);
        if (marker === 0xe0) {
          const jfif = hex("4a46494600010100004800480000");
          const unit = hex("4a46494600010100000100010000");
          if (
            offset !== 2 || (!equal(payload, jfif) && !equal(payload, unit))
          ) return invalidHistory();
        } else if (marker === 0xe1) {
          if (!equal(payload, exif)) return invalidHistory();
        } else if (marker === 0xed) {
          if (!equal(payload, emptyIptc)) return invalidHistory();
        } else return invalidHistory();
      },
    );
    if (size.width !== edge || size.height !== edge) return invalidHistory();
  } catch (error) {
    if (error instanceof JpegContainerRejected) return invalidHistory();
    throw error;
  }
}

function webp(bytes: Uint8Array, edge: number) {
  if (bytes.length < 26) return invalidHistory();
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const tag = (at: number) =>
    String.fromCharCode(...bytes.subarray(at, at + 4));
  const u24 = (at: number) =>
    bytes[at] + bytes[at + 1] * 256 + bytes[at + 2] * 65536;
  if (
    tag(0) !== "RIFF" || tag(8) !== "WEBP" ||
    view.getUint32(4, true) !== bytes.length - 8
  ) return invalidHistory();
  let pos = 12, image = false, extended = false;
  for (let count = 0; count < 2 && pos < bytes.length; count++) {
    if (bytes.length - pos < 8) return invalidHistory();
    const kind = tag(pos),
      length = view.getUint32(pos + 4, true),
      data = pos + 8;
    if (length > bytes.length - data) return invalidHistory();
    const end = data + length, padded = end + (length % 2);
    if (padded > bytes.length || (length % 2 && bytes[end] !== 0)) {
      return invalidHistory();
    }
    if (kind === "VP8X") {
      if (
        pos !== 12 || extended || length !== 10 || bytes[data] !== 0 ||
        bytes[data + 1] || bytes[data + 2] || bytes[data + 3] ||
        u24(data + 4) + 1 !== edge || u24(data + 7) + 1 !== edge
      ) return invalidHistory();
      extended = true;
    } else if (kind === "VP8 ") {
      if (image || length < 11) return invalidHistory();
      const header = u24(data), partition = header >>> 5;
      if (
        (header & 1) !== 0 || ((header >>> 1) & 7) > 3 || !(header & 16) ||
        partition === 0 || partition >= length - 10 ||
        bytes[data + 3] !== 0x9d || bytes[data + 4] !== 1 ||
        bytes[data + 5] !== 0x2a ||
        view.getUint16(data + 6, true) !== edge ||
        view.getUint16(data + 8, true) !== edge
      ) return invalidHistory();
      image = true;
    } else if (kind === "VP8L") {
      if (image || length < 6 || bytes[data] !== 0x2f) return invalidHistory();
      const header = view.getUint32(data + 1, true);
      if (
        (header >>> 28) !== 0 || (header & 0x3fff) + 1 !== edge ||
        ((header >>> 14) & 0x3fff) + 1 !== edge
      ) return invalidHistory();
      image = true;
    } else return invalidHistory();
    pos = padded;
  }
  if (!image || pos !== bytes.length) return invalidHistory();
}
