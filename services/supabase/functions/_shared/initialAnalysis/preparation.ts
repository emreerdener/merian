import { decodeBase64 } from "../encoding.ts";
import { processWavBuffer } from "../audioProcessing.ts";
import {
  hex,
  initialDigest,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { validateInitialInput } from "./schema.ts";
import type { InitialInput } from "./semantics.ts";

const prepared = new WeakSet<object>();
export interface PreparedInitialAdmission {
  readonly canonicalInput: string;
  readonly submissionDigest: string;
}

function matchesContainer(bytes: Uint8Array, type: string): boolean {
  const prefix = (...values: number[]) =>
    values.every((v, i) => bytes[i] === v);
  const ascii = (start: number, length: number) =>
    new TextDecoder().decode(bytes.subarray(start, start + length));
  switch (type) {
    case "image/jpeg":
      return bytes.length >= 4 && prefix(255, 216, 255);
    case "image/png":
      return prefix(137, 80, 78, 71, 13, 10, 26, 10);
    case "image/webp":
      return bytes.length >= 12 && ascii(0, 4) === "RIFF" &&
        ascii(8, 4) === "WEBP";
    case "image/heic":
    case "image/heif":
      return bytes.length >= 16 && ascii(4, 4) === "ftyp" &&
        ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].includes(ascii(8, 4));
    case "video/mp4":
      return bytes.length >= 16 && ascii(4, 4) === "ftyp" &&
        ["isom", "iso2", "mp41", "mp42", "avc1", "M4V "].includes(ascii(8, 4));
    case "audio/wav":
      return bytes.length >= 44 && ascii(0, 4) === "RIFF" &&
        ascii(8, 4) === "WAVE";
    default:
      return false;
  }
}
async function digest(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)));
}

/** The caller supplies the already accepted semantic values and fetched inline
 * or owned staged bytes. No URL/key, caller digest, or decorated prompt supplies
 * identity. Ownership, immutable retention and later promotion remain separate
 * required owners; this in-memory preparation cannot authorize dispatch.
 */
export async function prepareInitialAdmission(
  input: unknown,
  mediaSources: readonly Uint8Array[] = [],
): Promise<PreparedInitialAdmission> {
  const canonicalInput = validateInitialInput(input);
  const frozen = parseInitialCanonicalText(
    canonicalInput,
  ) as unknown as InitialInput;
  if (frozen.experiment !== null) {
    throw new Error("initial_analysis_experiment_unavailable");
  }
  if (mediaSources.length !== frozen.media.length) invalidInitialInput();
  // Copy every source before the first await, including views into shared buffers.
  const sources = mediaSources.map((source) => new Uint8Array(source));
  for (let i = 0; i < sources.length; i++) {
    const source = sources[i], item = frozen.media[i];
    if (
      source.length !== item.source_byte_count ||
      !matchesContainer(source, item.source_content_type) ||
      await digest(source) !== item.source_sha256
    ) invalidInitialInput();
    const consumed = item.kind === "audio"
      ? new Uint8Array(
        decodeBase64(
          processWavBuffer(source.buffer, 16000, {
            preserveSourceWhenTrimmedTooShort: item.clip_index !== null,
          }).base64Audio,
        ),
      )
      : source;
    if (
      consumed.length !== item.byte_count ||
      await digest(consumed) !== item.sha256
    ) invalidInitialInput();
  }
  const result = Object.freeze({
    canonicalInput,
    submissionDigest: await initialDigest("input", canonicalInput),
  });
  prepared.add(result);
  return result;
}
export function assertPreparedInitialAdmission(
  value: PreparedInitialAdmission,
): void {
  if (!prepared.has(value)) invalidInitialInput();
}
