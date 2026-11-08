import { MEDIA_BUDGETS } from "../mediaBudgets.ts";
import { invalidHistory } from "./contract.ts";

export type RetainedVideoBox = Readonly<{
  type: string;
  start: number;
  payloadStart: number;
  end: number;
}>;

/** Syntax/retained-output shape only, never byte verification or admission.
 * Payloads are opaque: this cannot establish self-contained media, codec/track
 * validity, timing, metadata absence, decodability or source derivation.
 * Synchronous inspection returns immutable offsets, not references to bytes.
 */
export function inspectRetainedVideoEnvelope(
  bytes: Uint8Array,
): readonly RetainedVideoBox[] {
  if (bytes.length < 8 || bytes.length > MEDIA_BUDGETS.maxVideoRawBytes) {
    return invalidHistory();
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const boxes: RetainedVideoBox[] = [];
  const required = new Set(["ftyp", "moov", "mdat"]);
  let start = 0;
  while (start < bytes.length) {
    if (boxes.length >= 32 || bytes.length - start < 8) return invalidHistory();
    const type = String.fromCharCode(...bytes.subarray(start + 4, start + 8));
    if (!["ftyp", "moov", "mdat", "free", "wide"].includes(type)) {
      return invalidHistory();
    }
    let size = view.getUint32(start), header = 8;
    if (size === 1) {
      if (bytes.length - start < 16) return invalidHistory();
      const extended = view.getBigUint64(start + 8);
      // Bound before conversion: no unsafe integer or end-offset arithmetic.
      if (extended > BigInt(bytes.length - start)) return invalidHistory();
      size = Number(extended);
      header = 16;
    }
    // Zero-to-EOF boxes are outside this closed retained-output envelope.
    if (size < header || size > bytes.length - start) return invalidHistory();
    if (boxes.length === 0 && type !== "ftyp") return invalidHistory();
    if (type !== "free" && type !== "wide") {
      if (!required.delete(type) || size === header) return invalidHistory();
    }
    const end = start + size;
    boxes.push(
      Object.freeze({ type, start, payloadStart: start + header, end }),
    );
    start = end;
  }
  if (required.size !== 0) return invalidHistory();
  return Object.freeze(boxes);
}
