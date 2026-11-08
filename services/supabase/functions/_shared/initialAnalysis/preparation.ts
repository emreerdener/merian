import { matchesInitialMediaContainer } from "./mediaContainer.ts";
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
      !matchesInitialMediaContainer(source, item.source_content_type) ||
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
