import { invalidHistory } from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import { inspectRetainedVideoStructure } from "./retainedVideoStructure.ts";
import { parsePreparedVideoManifest } from "./videoManifest.ts";

/** Private byte/metadata verification only; no decoding, derivation or admission authority. */
export async function verifyPreparedVideoSource(
  value: unknown,
  observationID: string,
  analysisID: string,
  input: Uint8Array,
): Promise<Uint8Array> {
  const manifest = parsePreparedVideoManifest(value, observationID, analysisID);
  const { source, parameters, audio } = manifest.provenance;
  // Parsing bounds the source size before allocation. Neither caller-owned
  // manifest objects nor bytes may change the verified result across hashing.
  if (input.byteLength !== source.byte_count) return invalidHistory();
  const bytes = new Uint8Array(input);
  const facts = inspectRetainedVideoStructure(bytes);
  if (
    facts.durationTicks !== parameters.duration_ticks ||
    facts.hasAudio !== (audio !== null)
  ) return invalidHistory();
  if (await evidenceDigest(bytes) !== source.sha256) return invalidHistory();
  return bytes;
}
