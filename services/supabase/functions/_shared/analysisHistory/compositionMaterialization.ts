import { verifyCompositionEvidenceItem } from "./compositionVerification.ts";
import type { IdentifyEvidence, MultimodalAIRequest } from "../ai/contracts.ts";
import { encodeBase64 } from "../encoding.ts";
import { parseCompositionRequestStructure } from "./compositionAdmission.ts";
import {
  type CompositionEvidenceReceipt,
  decodeCompositionEvidenceReceipt,
} from "./compositionEvidence.ts";
import { invalidHistory } from "./contract.ts";

type Item = CompositionEvidenceReceipt["items"][number];

/** Prepared whole-composition read boundary. The trusted caller owns server
 * authorization, deletion fences and the deadline. Every artifact is verified
 * before any provider evidence is returned; source clips remain private.
 */
export async function materializeCompositionAnalysis(
  value: unknown,
  owner: string,
  receiptBytes: Uint8Array,
  storage: {
    read(
      item: Item,
      options: { maximumBytes: number; signal: AbortSignal },
    ): Promise<Uint8Array>;
  },
  signal: AbortSignal,
): Promise<MultimodalAIRequest> {
  signal.throwIfAborted();
  const input = parseCompositionRequestStructure(value);
  const receipt = await decodeCompositionEvidenceReceipt(
    receiptBytes,
    input,
    owner,
  );
  signal.throwIfAborted();
  if (receipt.state !== "ready") return invalidHistory();
  const verified = new Map<string, Uint8Array>();
  for (const item of receipt.items) {
    signal.throwIfAborted();
    const returned = await storage.read(item, {
      maximumBytes: item.byte_count,
      signal,
    });
    signal.throwIfAborted();
    const bytes = await verifyCompositionEvidenceItem(
      input,
      item.media_id,
      returned,
    );
    signal.throwIfAborted();
    // The retained clip is required for provenance verification, not provider
    // input. Release its verified copy before reading the derived artifacts.
    if (item.role !== "video_source") verified.set(item.media_id, bytes);
  }
  const evidence: IdentifyEvidence[] = [];
  let imageIndex = 0, audioIndex = 0, videoIndex = 0, frames = 0;
  const body = (mediaID: string) => {
    const bytes = verified.get(mediaID);
    if (!bytes) return invalidHistory();
    return encodeBase64(bytes);
  };
  for (const node of input.evidence_manifest.items) {
    signal.throwIfAborted();
    if (node.kind === "description") {
      evidence.push({
        kind: "text",
        source: "observation_context",
        order: evidence.length,
        text: node.text,
      });
    } else if (node.kind === "image") {
      evidence.push({
        kind: "image",
        order: evidence.length,
        inputIndex: imageIndex++,
        lineage: null,
        ...(node.focus_region ? { focusRegion: node.focus_region } : {}),
        mimeType: node.artifact.content_type,
        data: body(node.artifact.media_id),
      });
    } else if (node.kind === "audio") {
      evidence.push({
        kind: "audio",
        order: evidence.length,
        inputIndex: audioIndex++,
        lineage: null,
        mimeType: "audio/wav",
        data: body(node.artifact.media_id),
      });
    } else if (node.kind === "video") {
      for (const frame of node.provenance.frames) {
        evidence.push({
          kind: "image",
          order: evidence.length,
          inputIndex: imageIndex++,
          lineage: {
            kind: "video_frame",
            clipIndex: videoIndex,
            frameIndex: frame.index,
          },
          mimeType: frame.artifact.content_type,
          data: body(frame.artifact.media_id),
        });
        frames++;
      }
      if (node.provenance.audio) {
        evidence.push({
          kind: "audio",
          order: evidence.length,
          inputIndex: audioIndex++,
          lineage: { kind: "video_audio", clipIndex: videoIndex },
          mimeType: "audio/wav",
          data: body(node.provenance.audio.artifact.media_id),
        });
      }
      videoIndex++;
    } else return invalidHistory();
  }
  signal.throwIfAborted();
  return {
    task: "identify",
    variant: "multimodal",
    evidence,
    capture: {
      hasVideo: videoIndex > 0,
      videoClipCount: videoIndex,
      declaredVideoFrameCount: frames,
      videoInferenceFrameCount: frames,
    },
  };
}
