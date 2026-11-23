import type { IdentifyEvidence, MultimodalAIRequest } from "../ai/contracts.ts";
import { encodeBase64 } from "../encoding.ts";
import { initialDeadline } from "../initialAnalysis/transport.ts";
import { invalidHistory } from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import { validateInitialPreparedAudioContainer } from "./initialEvidenceCapturePlan.ts";
import {
  type InitialRetentionRepository,
  initialRetentionRequest,
  type InitialRetentionStorage,
  parseInitialRetentionReceipt,
} from "./initialEvidenceRetention.ts";

/** Provider projection for the ordinary V9 successor. All source/playback bytes
 * were verified by retention and stay private. Only prepared artifacts are read
 * here, with fresh owner/readiness checks before each read and before returning.
 * No DSP, quota, provider dispatch or completion authority is granted here. */
export async function materializeInitialEvidence(
  owner: string,
  candidate: unknown,
  repository: Pick<InitialRetentionRepository, "reserve">,
  storage: Pick<InitialRetentionStorage, "readVerified">,
  signal: AbortSignal,
): Promise<MultimodalAIRequest> {
  signal.throwIfAborted();
  const request = await initialRetentionRequest(candidate);
  if (request.evidence_manifest.schema_version !== 9) return invalidHistory();
  let previous: ReturnType<typeof parseInitialRetentionReceipt> | undefined;
  async function authorize() {
    signal.throwIfAborted();
    const receipt = parseInitialRetentionReceipt(
      await repository.reserve(owner, request, signal),
      owner,
      request,
      previous,
    );
    signal.throwIfAborted();
    if (receipt.items.some((item) => !item.ready)) return invalidHistory();
    previous = receipt;
    return receipt;
  }
  async function body(media: string, role: string) {
    const receipt = await authorize();
    const item = receipt.items.find((item) => item.media_id === media);
    if (!item || item.role !== role) return invalidHistory();
    return await initialDeadline(signal, 30_000, async (current) => {
      const bytes = await storage.readVerified(item, current);
      current.throwIfAborted();
      if (!(bytes instanceof Uint8Array) || bytes.length !== item.byte_count) {
        return invalidHistory();
      }
      const owned = bytes.slice();
      try {
        if (await evidenceDigest(owned) !== item.sha256) {
          return invalidHistory();
        }
        current.throwIfAborted();
        if (role === "prepared_audio" || role === "prepared_companion_audio") {
          validateInitialPreparedAudioContainer(owned);
        }
        return encodeBase64(owned);
      } finally {
        owned.fill(0);
      }
    });
  }
  const evidence: IdentifyEvidence[] = [];
  let imageIndex = 0, audioIndex = 0, videoIndex = 0, frames = 0;
  for (const node of request.evidence_manifest.items) {
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
        mimeType: node.prepared.content_type,
        data: await body(node.prepared.media_id, "prepared_image"),
      });
    } else if (node.kind === "audio") {
      evidence.push({
        kind: "audio",
        order: evidence.length,
        inputIndex: audioIndex++,
        lineage: null,
        mimeType: "audio/wav",
        data: await body(node.prepared.media_id, "prepared_audio"),
      });
    } else {
      for (const [frameIndex, frame] of node.frames.entries()) {
        evidence.push({
          kind: "image",
          order: evidence.length,
          inputIndex: imageIndex++,
          lineage: { kind: "video_frame", clipIndex: videoIndex, frameIndex },
          mimeType: frame.content_type,
          data: await body(frame.media_id, "inference_frame"),
        });
        frames++;
      }
      if (node.audio) {
        evidence.push({
          kind: "audio",
          order: evidence.length,
          inputIndex: audioIndex++,
          lineage: { kind: "video_audio", clipIndex: videoIndex },
          mimeType: "audio/wav",
          data: await body(
            node.audio.prepared.media_id,
            "prepared_companion_audio",
          ),
        });
      }
      videoIndex++;
    }
  }
  await authorize();
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
