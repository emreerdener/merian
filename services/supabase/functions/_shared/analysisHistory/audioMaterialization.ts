import type { IdentifyEvidence } from "../ai/contracts.ts";
import { encodeBase64 } from "../encoding.ts";
import { parsePreparedAudioAdmission } from "./audioAdmission.ts";
import { validatePreparedAudioContainer } from "./audioContainer.ts";
import { historyUUID, invalidHistory } from "./contract.ts";
import {
  evidenceDigest,
  type EvidenceReceipt,
  parseAudioEvidenceReceipt,
} from "./evidence.ts";

/** Only exact admitted receipts and reverified bytes become provider evidence. */
export async function materializeAudioAnalysis(
  value: unknown,
  owner: string,
  receipts: unknown,
  storage: { readVerified(receipt: EvidenceReceipt): Promise<Uint8Array> },
): Promise<IdentifyEvidence[]> {
  const input = parsePreparedAudioAdmission(value);
  historyUUID(owner);
  if (!Array.isArray(receipts) || receipts.length !== 1) {
    return invalidHistory();
  }
  const evidence: IdentifyEvidence[] = [];
  for (const item of input.evidence_manifest.items) {
    if (item.kind === "description") {
      evidence.push({
        kind: "text",
        order: evidence.length,
        source: "observation_context",
        text: item.text,
      });
      continue;
    }
    const identity = {
      owner_id: owner,
      observation_id: input.observation_id,
      analysis_id: input.analysis_id,
      media_id: item.media_id,
    };
    const receipt = parseAudioEvidenceReceipt(receipts[0], identity, {
      ...identity,
      ...item,
    });
    if (receipt.ready_at === null) return invalidHistory();
    // Own returned bytes across awaits even for an injected transport.
    const bytes = (await storage.readVerified(receipt)).slice();
    validatePreparedAudioContainer(bytes);
    if (
      bytes.length !== item.byte_count ||
      await evidenceDigest(bytes) !== item.sha256
    ) return invalidHistory();
    evidence.push({
      kind: "audio",
      order: evidence.length,
      data: encodeBase64(bytes),
      mimeType: "audio/wav",
      inputIndex: 0,
      lineage: null,
    });
  }
  return evidence;
}
