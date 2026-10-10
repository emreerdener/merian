import { exactObject, invalidHistory } from "./contract.ts";
import { verifyPreparedVideoSource } from "./retainedVideoContainer.ts";
import { parsePreparedVideoAdmission } from "./videoAdmission.ts";
import { verifyPreparedVideoAudio } from "./videoAudioContainer.ts";
import {
  decodeVideoEvidenceReceipt,
  type VideoEvidenceReceipt,
} from "./videoEvidence.ts";
import { verifyPreparedVideoFrame } from "./videoFrameContainer.ts";

type Item = VideoEvidenceReceipt["items"][number];

/** Prepared whole-cohort byte boundary. Caller owns authentication, current SQL
 * fences and the abort deadline. No upload, readiness write, derivation proof or
 * dispatch authority is conferred. Never regenerates missing or invalid outputs.
 */
export async function materializeVideoCohort(
  candidate: unknown,
  owner: string,
  receiptBytes: Uint8Array,
  storage: {
    // Adapter must bound the read before buffering and honor the supplied signal.
    read(
      item: Item,
      options: { maximumBytes: number; signal: AbortSignal },
    ): Promise<Uint8Array>;
  },
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const envelope = exactObject(candidate, [
    "schema_version",
    "input",
    "fingerprint_version",
    "fingerprint",
  ]);
  const input = parsePreparedVideoAdmission(envelope.input);
  const receipt = await decodeVideoEvidenceReceipt(receiptBytes, {
    ...envelope,
    input,
  }, owner);
  signal.throwIfAborted();
  if (receipt.state !== "ready") return invalidHistory();
  const items: { item: Item; bytes: Uint8Array }[] = [];
  for (const item of receipt.items) {
    signal.throwIfAborted();
    const returned = await storage.read(item, {
      maximumBytes: item.byte_count,
      signal,
    });
    signal.throwIfAborted();
    // Reject oversize before any owned-copy allocation. Existing verifiers copy
    // synchronously before their digest await, so injected buffers cannot alias.
    if (
      !(returned instanceof Uint8Array) ||
      returned.byteLength !== item.byte_count
    ) return invalidHistory();
    const args = [
      input.evidence_manifest,
      input.observation_id,
      input.analysis_id,
    ] as const;
    const bytes = item.role === "source"
      ? await verifyPreparedVideoSource(...args, returned)
      : item.role === "frame"
      ? await verifyPreparedVideoFrame(...args, item.index!, returned)
      : await verifyPreparedVideoAudio(...args, returned);
    signal.throwIfAborted();
    items.push(Object.freeze({ item, bytes }));
  }
  // No partial result escapes on read, digest, container or cancellation failure.
  return Object.freeze({ receipt, items: Object.freeze(items) });
}
