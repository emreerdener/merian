import { inspectPreparedAudioContainer } from "./audioContainer.ts";
import { invalidHistory } from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import { parsePreparedVideoManifest } from "./videoManifest.ts";

/** Private byte check, not upload/admission authority or proof of derivation.
 * Returns an owned copy so a caller cannot change bytes across digest awaits.
 * No live V4 path is enabled until cohort, execution and reader integration.
 */
export async function verifyPreparedVideoAudio(
  value: unknown,
  observationID: string,
  analysisID: string,
  input: Uint8Array,
): Promise<Uint8Array> {
  const audio = parsePreparedVideoManifest(value, observationID, analysisID)
    .provenance.audio;
  if (audio === null || input.length !== audio.artifact.byte_count) {
    return invalidHistory();
  }
  // The parsed manifest bounds the allocation before we copy.
  const bytes = input.slice();
  const inspected = inspectPreparedAudioContainer(bytes);
  if (
    inspected.sampleCount !== audio.sample_count ||
    await evidenceDigest(bytes) !== audio.artifact.sha256
  ) return invalidHistory();
  return bytes;
}
