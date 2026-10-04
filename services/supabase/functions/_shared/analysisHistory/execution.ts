import type {
  AIExecutionOutcome,
  PreparedAIExecution,
} from "../ai/contracts.ts";
import { identificationProvenance } from "../ai/provenance.ts";
import { identificationUsageFacts } from "../ai/identificationUsage.ts";
import { prepareMultimodalResultPolicy } from "../ai/multimodalResultPolicy.ts";
import { normalizeIdentification } from "../identify/normalizeIdentification.ts";
import { parseIdentifySuccessEnvelope } from "../identify/contract.ts";
import { isProviderSafetyRejected } from "../identify/moderation.ts";
import type { ResolvedAnalysisSpecies } from "./append.ts";
import { buildAdmittedObservationDraft } from "./intent.ts";
import { buildProtectedAnalysisDraft } from "./protectedManifest.ts";
import {
  exactObject,
  HISTORY_MAX_RESULT_BYTES,
  historyUUID,
  invalidHistory,
} from "./contract.ts";

export type AnalysisState =
  | "admitted"
  | "dispatched"
  | "draft"
  | "complete"
  | "failed_terminal";
export interface AnalysisWork {
  state: AnalysisState;
  claimed: boolean;
  work_token?: string;
  input?: Record<string, unknown>;
  quota?: Record<string, unknown>;
  provider_outcome?: SavedAnalysisOutcome | null;
}
export interface SavedAnalysisOutcome {
  schema_version: 1;
  provenance: ReturnType<typeof identificationProvenance>;
  outcome: { kind: "draft"; result: unknown } | {
    kind: "refusal" | "invalid_output";
  };
  usage: ReturnType<typeof identificationUsageFacts>;
}
export interface AnalysisExecutionDependencies {
  prepare(work: AnalysisWork): Promise<PreparedAIExecution>;
  advance(
    operation: string,
    payload: Record<string, unknown>,
  ): Promise<unknown>;
  resolveSpecies(
    result: ReturnType<typeof parseIdentifySuccessEnvelope>["data"],
  ): Promise<ResolvedAnalysisSpecies | null>;
}

/** Snapshot only bounded, canonical result content before any taxonomy I/O. */
export function captureAnalysisOutcome(
  result: AIExecutionOutcome,
  work: AnalysisWork,
): SavedAnalysisOutcome | null {
  if (
    result.kind === "unknown_execution" || result.kind === "operational_failure"
  ) return null;
  const provenance = identificationProvenance(result.execution);
  const usage = identificationUsageFacts(result);
  let outcome: SavedAnalysisOutcome["outcome"];
  if (result.kind !== "draft") outcome = { kind: result.kind };
  else {
    try {
      const policy = prepareMultimodalResultPolicy(result.execution);
      const safety = policy.safetySignals(result);
      if (isProviderSafetyRejected(safety.finishReason, safety.safetyRatings)) {
        outcome = { kind: "refusal" };
      } else {
        const normalized = normalizeIdentification(result.draft, {
          hasVisualEvidence: work.input?.schema_version === 2,
          hasAudioEvidence: false,
          hasInvasiveLocationContext: false,
          confidencePolicy: policy.confidence,
        });
        const data = normalized.identification;
        const payload = parseIdentifySuccessEnvelope({
          success: true,
          data: {
            ...data,
            scan_id: historyUUID(work.input?.observation_id),
            colors: [],
            estimated_size_cm: null,
            inference_tier: work.quota?.effective_tier === "pro"
              ? "pro"
              : "flash",
            life_stage: normalized.clientLifeStage,
            candidates: normalized.clientCandidates,
            pet_identification: data.pet_identification ?? null,
            insight_data: {
              ai_reasoning: data.ai_reasoning,
              hazard_type: "none",
            },
            identification_provenance: provenance,
          },
        }).data;
        outcome = { kind: "draft", result: payload };
      }
    } catch {
      // Received but invalid/unsafe content is proven terminal, never another call.
      outcome = { kind: "invalid_output" };
    }
  }
  const saved: SavedAnalysisOutcome = {
    schema_version: 1,
    provenance,
    outcome,
    usage,
  };
  if (
    new TextEncoder().encode(JSON.stringify(saved)).length >
      HISTORY_MAX_RESULT_BYTES - 4096
  ) {
    saved.outcome = { kind: "invalid_output" };
  }
  return saved;
}

/** One claimed operation. No retries of inference and no selection mutation. */
export async function executeObservationAnalysis(
  work: AnalysisWork,
  deps: AnalysisExecutionDependencies,
): Promise<AnalysisState> {
  if (!work.claimed) return work.state;
  historyUUID(work.work_token);
  if (!work.input || !work.quota) return invalidHistory();
  let state = work.state;
  try {
    let saved = work.provider_outcome;
    if (state === "admitted") {
      const prepared = await deps.prepare(work);
      prepareMultimodalResultPolicy(prepared.snapshot);
      // An uncertain commit is NOT permission to invoke. A live worker may
      // prove non-invocation below; otherwise a retry reads the saved state.
      let dispatch: unknown;
      try {
        dispatch = await deps.advance("dispatch", {
          provenance: identificationProvenance(prepared.snapshot),
        });
      } catch (error) {
        // This live worker knows invoke() was never entered. Only its still-live
        // claim can terminalize; expiry/crash/uncertain cancellation stays held.
        await deps.advance("cancel_uninvoked", {}).catch(() => {});
        throw error;
      }
      if (
        !dispatch || typeof dispatch !== "object" ||
        !("may_dispatch" in dispatch) || dispatch.may_dispatch !== true
      ) return "dispatched";
      state = "dispatched";
      const result = await prepared.invoke();
      saved = captureAnalysisOutcome(result, work);
      if (!saved) return state;
      await deps.advance("outcome", {
        quota_token: historyUUID(work.quota.lease_token),
        value: saved,
      });
    }
    if (state === "dispatched") {
      if (!saved) return state;
      exactObject(saved, ["schema_version", "provenance", "outcome", "usage"]);
      if (saved.schema_version !== 1) return invalidHistory();
      if (
        saved.outcome.kind === "refusal" ||
        saved.outcome.kind === "invalid_output"
      ) {
        await deps.advance("fail", {
          reason: saved.outcome.kind === "refusal"
            ? "provider_refusal"
            : "invalid_result",
        });
        return "failed_terminal";
      }
      if (saved.outcome.kind !== "draft") return invalidHistory();
      const result = parseIdentifySuccessEnvelope({
        success: true,
        data: saved.outcome.result,
      }).data;
      const species = await deps.resolveSpecies(result);
      const builder = work.input.schema_version === 2
        ? buildProtectedAnalysisDraft
        : buildAdmittedObservationDraft;
      const draft = builder(JSON.stringify(work.input), result, species);
      await deps.advance("draft", { draft });
      state = "draft";
    }
    if (state === "draft") {
      await deps.advance("complete", {});
      return "complete";
    }
    return state;
  } finally {
    // Failure leaves durable state for recovery. Never masks the original error,
    // releases a credit, or changes a newer worker's lease.
    await deps.advance("release", {}).catch(() => {});
  }
}
