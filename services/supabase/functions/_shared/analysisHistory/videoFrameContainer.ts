import { invalidHistory } from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import {
  inspectJpegContainer,
  JpegContainerRejected,
} from "./jpegContainer.ts";
import {
  inspectWebpContainer,
  WebpContainerRejected,
} from "./webpContainer.ts";
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
  try {
    const size = inspectWebpContainer(bytes, {
      maximumBytes: 33_554_432,
      maximumWidth: edge,
      maximumHeight: edge,
      maximumPixels: edge * edge,
    }, "opaque_frame");
    if (size.width !== edge || size.height !== edge) return invalidHistory();
  } catch (error) {
    if (error instanceof WebpContainerRejected) return invalidHistory();
    throw error;
  }
}
