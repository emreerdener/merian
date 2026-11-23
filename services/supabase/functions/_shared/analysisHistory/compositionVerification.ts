import { validatePreparedAudioContainer } from "./audioContainer.ts";
import { parseCompositionRequestStructure } from "./compositionAdmission.ts";
import { compositionCohortItems } from "./compositionCohort.ts";
import { invalidHistory } from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import { verifyPreparedVideoSource } from "./retainedVideoContainer.ts";
import { verifyPreparedVideoAudio } from "./videoAudioContainer.ts";
import { verifyPreparedVideoFrame } from "./videoFrameContainer.ts";

/** Same exact-byte verification for upload and provider materialization.
 * Derive membership from the complete immutable manifest, never caller metadata.
 * Photo bytes retain the existing private photo transport policy; WAV and video
 * artifacts additionally pass their existing closed container validators.
 */
export async function verifyCompositionEvidenceItem(
  value: unknown,
  mediaID: string,
  returned: Uint8Array,
): Promise<Uint8Array> {
  const input = parseCompositionRequestStructure(value);
  const item = compositionCohortItems(input).find((item) =>
    item.media_id === mediaID
  );
  if (
    !item || !(returned instanceof Uint8Array) ||
    returned.byteLength !== item.byte_count
  ) return invalidHistory();
  const body = returned.slice();
  const node = input.evidence_manifest.items[item.node_index];
  if (node.kind === "video") {
    const manifest = {
      schema_version: 4,
      provenance: node.provenance,
      descriptions: [],
    };
    const args = [manifest, input.observation_id, input.analysis_id] as const;
    if (item.role === "video_source") {
      return await verifyPreparedVideoSource(...args, body);
    }
    if (item.role === "video_frame" && item.frame_index !== null) {
      return await verifyPreparedVideoFrame(...args, item.frame_index, body);
    }
    if (item.role === "video_audio") {
      return await verifyPreparedVideoAudio(...args, body);
    }
    return invalidHistory();
  }
  if (item.role === "audio") validatePreparedAudioContainer(body);
  else if (item.role !== "image") return invalidHistory();
  if (await evidenceDigest(body) !== item.sha256) return invalidHistory();
  return body;
}
