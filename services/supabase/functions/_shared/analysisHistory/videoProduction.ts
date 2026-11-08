import type { SupabaseClient } from "@supabase/supabase-js";
import type { IdentifyEvidence, MultimodalAIRequest } from "../ai/contracts.ts";
import { prepareAIExecution } from "../ai/production.ts";
import { encodeBase64 } from "../encoding.ts";
import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { PrivateHistoryEvidenceStorage } from "./evidenceStorage.ts";
import { analysisAuthority, historyWorkerRPC } from "./production.ts";
import { parsePreparedVideoAdmission } from "./videoAdmission.ts";
import {
  executeVideoObservationAnalysis,
  parseVideoAnalysisWork,
} from "./videoExecution.ts";
import { materializeVideoCohort } from "./videoMaterialization.ts";
import { videoSourceFingerprint } from "./videoSourceFingerprint.ts";

/** The retained source must validate, but only immutable derived media enter the
 * provider request. No video URL, source bytes or storage identity are forwarded. */
export async function materializeVideoAnalysis(
  value: unknown,
  owner: string,
  receipt: unknown,
  storage: Parameters<typeof materializeVideoCohort>[3],
  signal: AbortSignal,
): Promise<MultimodalAIRequest> {
  const input = parsePreparedVideoAdmission(value);
  const candidate = {
    schema_version: 2,
    input,
    fingerprint_version: 1,
    fingerprint: await videoSourceFingerprint(input),
  };
  const cohort = await materializeVideoCohort(
    candidate,
    owner,
    new TextEncoder().encode(JSON.stringify(receipt)),
    storage,
    signal,
  );
  const evidence: IdentifyEvidence[] = input.evidence_manifest.descriptions.map(
    (text, order) => ({
      kind: "text",
      source: "observation_context",
      order,
      text,
    }),
  );
  for (const { item, bytes } of cohort.items) {
    if (item.role === "source") continue;
    if (item.role === "frame") {
      if (item.index === null || item.index === undefined) {
        return invalidHistory();
      }
      evidence.push({
        kind: "image",
        order: evidence.length,
        data: encodeBase64(bytes),
        mimeType: item.content_type,
        inputIndex: item.index,
        lineage: { kind: "video_frame", clipIndex: 0, frameIndex: item.index },
      });
    } else {
      if (item.content_type !== "audio/wav") return invalidHistory();
      evidence.push({
        kind: "audio",
        order: evidence.length,
        data: encodeBase64(bytes),
        mimeType: "audio/wav",
        inputIndex: 0,
        lineage: { kind: "video_audio", clipIndex: 0 },
      });
    }
  }
  signal.throwIfAborted();
  return {
    task: "identify",
    variant: "multimodal",
    evidence,
    capture: {
      hasVideo: true,
      videoClipCount: 1,
      declaredVideoFrameCount: 5,
      videoInferenceFrameCount: 5,
    },
  };
}

export async function runOwnedVideoAnalysis(
  client: SupabaseClient,
  owner: string,
  observation: string,
  analysis: string,
  value: unknown,
  signal: AbortSignal = AbortSignal.timeout(110_000),
) {
  historyUUID(owner);
  historyUUID(observation);
  historyUUID(analysis);
  const work = parseVideoAnalysisWork(value, observation, analysis);
  const advance = (operation: string, payload: Record<string, unknown>) =>
    historyWorkerRPC(
      client,
      "advance_owned_observation_video_analysis",
      {
        p_owner: owner,
        p_observation: observation,
        p_analysis: analysis,
        p_work: work.work_token ?? null,
        p_operation: operation,
        p_payload: payload,
      },
      operation === "materialize" || operation === "dispatch"
        ? signal
        : undefined,
    );
  return await executeVideoObservationAnalysis(work, {
    advance,
    prepare: async (dispatchWork) => {
      const authority = analysisAuthority(owner, dispatchWork);
      const receipt = await advance("materialize", {});
      const storage = new PrivateHistoryEvidenceStorage();
      const request = await materializeVideoAnalysis(
        dispatchWork.input,
        owner,
        receipt,
        {
          read: (item, { signal }) => storage.readVerified(item, signal),
        },
        AbortSignal.any([signal, AbortSignal.timeout(20_000)]),
      );
      return prepareAIExecution(request, authority);
    },
    resolveSpecies: async () => {
      const value = await advance("resolve_species", {});
      if (value === null) return null;
      const row = exactObject(value, ["id", "scientific_name"]);
      if (
        typeof row.scientific_name !== "string" ||
        !row.scientific_name.trim() || row.scientific_name.length > 255
      ) return invalidHistory();
      return { id: historyUUID(row.id), scientific_name: row.scientific_name };
    },
  }, signal);
}
