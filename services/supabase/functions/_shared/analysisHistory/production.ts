import { publicationAbortable } from "./publicationDeadline.ts";
import { materializeAudioAnalysis } from "./audioMaterialization.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  assignmentMatchesModel,
  isIdentificationProviderAssignment,
} from "../ai/admission.ts";
import type {
  IdentifyEvidence,
  UserRequestAuthority,
} from "../ai/contracts.ts";
import { prepareAIExecution } from "../ai/production.ts";
import { encodeBase64 } from "../encoding.ts";
import { parseCapturedMediaWireV1 } from "../capturedMediaContract.ts";

import { HistoryError, historyUUID, invalidHistory } from "./contract.ts";
import { parseExecutableAnalysisInput } from "./analysisInput.ts";
import { parseEvidenceReceipt } from "./evidence.ts";
import { PrivateHistoryEvidenceStorage } from "./evidenceStorage.ts";
import { parseProtectedEvidenceManifest } from "./protectedManifest.ts";
import { type AnalysisWork, executeObservationAnalysis } from "./execution.ts";

export async function historyWorkerRPC(
  client: SupabaseClient,
  name: string,
  args: Record<string, unknown>,
  parentSignal?: AbortSignal,
): Promise<unknown> {
  const deadline = AbortSignal.timeout(12_000);
  const signal = parentSignal
    ? AbortSignal.any([parentSignal, deadline])
    : deadline;
  const { data, error } = await publicationAbortable(
    signal,
    () => client.rpc(name, args).abortSignal(signal),
  );
  if (error) {
    if (error.message === "analysis_history_not_found") {
      throw new HistoryError("analysis_history_not_found");
    }
    // Admission compares immutable request identity. Later worker conflicts can
    // instead mean an expired claim, whose saved work remains recoverable.
    if (
      (name === "begin_owned_observation_analysis" ||
        name === "begin_owned_observation_video_analysis") &&
      error.message === "analysis_history_operation_conflict"
    ) {
      throw new HistoryError("analysis_history_operation_conflict");
    }
    throw new HistoryError("analysis_history_unavailable");
  }
  return data;
}
export function analysisAuthority(
  owner: string,
  work: AnalysisWork,
): UserRequestAuthority {
  const q = work.quota;
  if (!q) return invalidHistory();
  const assignment = {
    inputProfile: q.input_profile,
    provider: q.provider,
    binding: q.binding,
    permission: q.processor_permission,
  };
  if (
    !isIdentificationProviderAssignment(assignment) ||
    typeof q.model !== "string" ||
    !assignmentMatchesModel(assignment, q.model) ||
    !Number.isSafeInteger(q.attempt_count) || (q.attempt_count as number) < 1 ||
    !Number.isSafeInteger(q.policy_version) ||
    (q.policy_version as number) < 1 ||
    (q.effective_tier !== "free" && q.effective_tier !== "pro")
  ) return invalidHistory();
  return {
    kind: "user_request",
    userId: historyUUID(owner),
    permission: assignment.permission,
    operation: "scan_identification",
    reservation: {
      assignment,
      id: historyUUID(q.reservation_id),
      requestId: historyUUID(q.request_id),
      attemptCount: q.attempt_count as number,
      policyVersion: q.policy_version as number,
      model: q.model,
      tier: { effective_tier: q.effective_tier },
    },
  };
}

export async function runOwnedAnalysis(
  client: SupabaseClient,
  owner: string,
  observation: string,
  analysis: string,
  value: unknown,
) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return invalidHistory();
  }
  const work = value as AnalysisWork;
  if (
    !["admitted", "dispatched", "draft", "complete", "failed_terminal"]
      .includes(work.state) || typeof work.claimed !== "boolean"
  ) return invalidHistory();
  const advance = (operation: string, payload: Record<string, unknown>) =>
    historyWorkerRPC(client, "advance_owned_observation_analysis", {
      p_owner: owner,
      p_observation: observation,
      p_analysis: analysis,
      p_work: work.work_token ?? null,
      p_operation: operation,
      p_payload: payload,
    });
  return await executeObservationAnalysis(work, {
    advance,
    prepare: async () => {
      const input = parseExecutableAnalysisInput(work.input);
      if (
        input.observation_id !== observation || input.analysis_id !== analysis
      ) return invalidHistory();
      const evidence: IdentifyEvidence[] = [];
      if (input.schema_version === 1) {
        const manifest = input.evidence_manifest as { captured_media: unknown };
        for (const item of parseCapturedMediaWireV1(manifest.captured_media)) {
          if (!("description" in item)) return invalidHistory();
          evidence.push({
            kind: "text",
            source: "observation_context",
            order: evidence.length,
            text: item.description._0.freeText,
          });
        }
      } else if (input.schema_version === 3) {
        const authority = analysisAuthority(owner, work);
        if (
          authority.reservation.assignment?.inputProfile !==
            "multimodal_audio_v1" ||
          authority.permission !== "google_gemini"
        ) return invalidHistory();
        evidence.push(
          ...await materializeAudioAnalysis(
            input,
            owner,
            await advance("materialize", {}),
            new PrivateHistoryEvidenceStorage(),
          ),
        );
      } else {
        const manifest = parseProtectedEvidenceManifest(
          input.evidence_manifest,
        );
        const receipts = await advance("materialize", {});
        if (
          !Array.isArray(receipts) ||
          receipts.length !==
            manifest.items.filter((item) => item.kind === "image").length
        ) return invalidHistory();
        const storage = new PrivateHistoryEvidenceStorage();
        let imageIndex = 0;
        for (const item of manifest.items) {
          if (item.kind === "description") {
            evidence.push({
              kind: "text",
              source: "observation_context",
              order: evidence.length,
              text: item.text,
            });
          } else {
            const identity = {
              owner_id: owner,
              observation_id: observation,
              analysis_id: analysis,
              media_id: item.media_id,
            };
            const receipt = parseEvidenceReceipt(
              receipts.find((row) => row?.media_id === item.media_id),
              identity,
              { ...identity, ...item },
            );
            if (receipt.ready_at === null) return invalidHistory();
            const bytes = await storage.readVerified(receipt);
            evidence.push({
              kind: "image",
              order: evidence.length,
              data: encodeBase64(bytes),
              mimeType: receipt.content_type,
              inputIndex: imageIndex++,
              lineage: null,
            });
          }
        }
      }
      return prepareAIExecution({
        task: "identify",
        variant: "multimodal",
        evidence,
        capture: {
          hasVideo: false,
          videoClipCount: 0,
          declaredVideoFrameCount: 0,
          videoInferenceFrameCount: 0,
        },
      }, analysisAuthority(owner, work));
    },
    resolveSpecies: async () => {
      const value = await advance("resolve_species", {});
      if (value === null) return null;
      if (
        !value || typeof value !== "object" || !("id" in value) ||
        !("scientific_name" in value) ||
        typeof value.scientific_name !== "string"
      ) return invalidHistory();
      return {
        id: historyUUID(value.id),
        scientific_name: value.scientific_name,
      };
    },
  });
}
