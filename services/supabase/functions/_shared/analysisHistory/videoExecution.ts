import { identificationProvenance } from "../ai/provenance.ts";
import { parseIdentifySuccessEnvelope } from "../identify/contract.ts";
import {
  exactObject,
  HISTORY_MAX_RESULT_BYTES,
  historyUUID,
  invalidHistory,
} from "./contract.ts";
import {
  type AnalysisExecutionDependencies,
  type AnalysisState,
  type AnalysisWork,
  assertVideoExecutionSnapshot,
  capturePreparedVideoOutcome,
} from "./execution.ts";
import {
  buildPreparedVideoDraft,
  parsePreparedVideoAdmission,
} from "./videoAdmission.ts";

export type VideoAnalysisWork = Omit<AnalysisWork, "provider_outcome"> & {
  provider_outcome?: unknown;
};

/** Snapshot the private service response before any await. No caller JSON can
 * supply a worker claim. Unknown dispatch cannot acquire execution authority. */
export function parseVideoAnalysisWork(
  value: unknown,
  observation: string,
  analysis: string,
): VideoAnalysisWork {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return invalidHistory();
  }
  const bytes = JSON.stringify(value);
  if (new TextEncoder().encode(bytes).length > 3 * HISTORY_MAX_RESULT_BYTES) {
    return invalidHistory();
  }
  const row = JSON.parse(bytes) as Record<string, unknown>;
  const state = row.state;
  if (
    (state !== "admitted" && state !== "dispatched" && state !== "draft" &&
      state !== "complete" && state !== "failed_terminal") ||
    typeof row.claimed !== "boolean"
  ) return invalidHistory();
  if (!row.claimed) {
    exactObject(row, ["state", "claimed"]);
    return { state, claimed: false };
  }
  if (
    row.state !== "admitted" && row.state !== "dispatched" &&
    row.state !== "draft"
  ) return invalidHistory();
  exactObject(
    row,
    row.state === "admitted"
      ? ["state", "claimed", "work_token", "input", "quota"]
      : [
        "state",
        "claimed",
        "work_token",
        "input",
        "quota",
        "provider_outcome",
        "draft",
      ],
  );
  historyUUID(row.work_token);
  const input = parsePreparedVideoAdmission(row.input);
  if (
    input.observation_id !== historyUUID(observation) ||
    input.analysis_id !== historyUUID(analysis)
  ) return invalidHistory();
  if (!row.quota || typeof row.quota !== "object" || Array.isArray(row.quota)) {
    return invalidHistory();
  }
  const q = row.quota as Record<string, unknown>;
  if (
    q.request_id !== analysis || q.original_analysis_id !== analysis ||
    q.attempt_count !== 1 ||
    q.provider !== "gemini" || q.binding !== "gemini_baseline_v1" ||
    q.processor_permission !== "google_gemini" ||
    q.input_profile !==
      (input.evidence_manifest.provenance.audio
        ? "multimodal_video_audio_v1"
        : "multimodal_video_frames_v1") ||
    !["free", "pro"].includes(String(q.effective_tier)) ||
    q.model !==
      (q.effective_tier === "pro" ? "gemini-2.5-pro" : "gemini-2.5-flash") ||
    !Number.isSafeInteger(q.policy_version) || (q.policy_version as number) < 1
  ) return invalidHistory();
  historyUUID(q.reservation_id);
  historyUUID(q.lease_token);
  if (row.state !== "admitted" && !row.provider_outcome) {
    return invalidHistory();
  }
  return {
    state,
    claimed: true,
    work_token: historyUUID(row.work_token),
    input,
    quota: q,
    provider_outcome: row.provider_outcome,
  };
}

/** Exactly one claimed V4 operation. Dispatch uncertainty never authorizes a
 * second invoke, cancellation, refund or regenerated media. */
export async function executeVideoObservationAnalysis(
  work: VideoAnalysisWork,
  deps: AnalysisExecutionDependencies,
  signal?: AbortSignal,
): Promise<AnalysisState> {
  if (!work.claimed) return work.state;
  const input = parsePreparedVideoAdmission(work.input);
  historyUUID(work.work_token);
  if (!work.quota) return invalidHistory();
  let state = work.state;
  try {
    let saved = work.provider_outcome;
    if (state === "admitted") {
      signal?.throwIfAborted();
      const dispatchWork: AnalysisWork = {
        state: work.state,
        claimed: true,
        work_token: work.work_token,
        input,
        quota: work.quota,
      };
      const prepared = await deps.prepare(dispatchWork);
      assertVideoExecutionSnapshot(dispatchWork, prepared.snapshot);
      signal?.throwIfAborted();
      const response = await deps.advance("dispatch", {
        provenance: identificationProvenance(prepared.snapshot),
      });
      const dispatch = exactObject(response, ["invocation_id", "may_dispatch"]);
      historyUUID(dispatch.invocation_id);
      if (typeof dispatch.may_dispatch !== "boolean") return invalidHistory();
      state = "dispatched";
      if (!dispatch.may_dispatch) return state;
      signal?.throwIfAborted();
      const result = await prepared.invoke();
      saved = capturePreparedVideoOutcome(result, dispatchWork);
      if (!saved) return state;
      await deps.advance("outcome", {
        quota_token: historyUUID(work.quota.lease_token),
        value: saved,
      });
    }
    if (state === "dispatched") {
      if (!saved) return state;
      const received = exactObject(saved, [
        "schema_version",
        "provenance",
        "outcome",
        "usage",
      ]);
      if (received.schema_version !== 1) return invalidHistory();
      const kind = received.outcome && typeof received.outcome === "object" &&
          "kind" in received.outcome
        ? received.outcome.kind
        : null;
      const outcome = exactObject(
        received.outcome,
        kind === "draft" ? ["kind", "result"] : ["kind"],
      );
      if (
        kind === "refusal" ||
        kind === "invalid_output"
      ) {
        await deps.advance("fail", {});
        return "failed_terminal";
      }
      if (kind !== "draft") return invalidHistory();

      const result = parseIdentifySuccessEnvelope({
        success: true,
        data: outcome.result,
      }).data;
      const species = await deps.resolveSpecies(result);
      const draft = buildPreparedVideoDraft(
        JSON.stringify(input),
        result,
        species,
      );
      await deps.advance("draft", { draft });
      await deps.advance("account", {});
      state = "draft";
    }
    if (state === "draft") {
      await deps.advance("complete", {});
      return "complete";
    }
    return state;
  } finally {
    // Await cleanup of this lease only. SQL refuses a replaced or expired token;
    // release cannot erase evidence, settle credits or mask the original error.
    await deps.advance("release", {}).catch(() => {});
  }
}
