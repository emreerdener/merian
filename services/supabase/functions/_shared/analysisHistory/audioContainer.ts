import { MEDIA_BUDGETS } from "../mediaBudgets.ts";
import { invalidHistory } from "./contract.ts";

/** Closed prepared PCM profile. This validates bytes, not ownership/readiness.
 * Accepts the compact header and Core Audio's zero-filled FLLR before data.
 * No trimming, resampling, decoding or metadata rewriting occurs here.
 */
export function inspectPreparedAudioContainer(bytes: Uint8Array) {
  if (bytes.length < 46 || bytes.length > MEDIA_BUDGETS.maxAudioRawBytes) {
    return invalidHistory();
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const tag = (offset: number, expected: string) =>
    [...expected].every((char, index) =>
      bytes[offset + index] === char.charCodeAt(0)
    );
  if (
    !tag(0, "RIFF") || view.getUint32(4, true) !== bytes.length - 8 ||
    !tag(8, "WAVE") || !tag(12, "fmt ") || view.getUint32(16, true) !== 16 ||
    view.getUint16(20, true) !== 1 || view.getUint16(22, true) !== 1 ||
    view.getUint32(24, true) !== 44100 || view.getUint32(28, true) !== 88200 ||
    view.getUint16(32, true) !== 2 || view.getUint16(34, true) !== 16
  ) return invalidHistory();
  let offset = 36;
  if (tag(offset, "FLLR")) {
    const count = view.getUint32(offset + 4, true);
    const end = offset + 8 + count + count % 2;
    if (
      count < 1 || count > 4096 || end > bytes.length - 10 ||
      bytes.subarray(offset + 8, end).some((byte) => byte !== 0)
    ) return invalidHistory();
    offset = end;
  }
  if (offset + 10 > bytes.length || !tag(offset, "data")) {
    return invalidHistory();
  }
  const count = view.getUint32(offset + 4, true);
  if (count < 2 || count % 2 !== 0 || offset + 8 + count !== bytes.length) {
    return invalidHistory();
  }
  return Object.freeze({ sampleCount: count / 2, dataOffset: offset + 8 });
}

/** Existing audio callers retain the same validation-only contract. */
export function validatePreparedAudioContainer(bytes: Uint8Array): void {
  inspectPreparedAudioContainer(bytes);
}
