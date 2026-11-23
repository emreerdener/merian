import { validateCompositionRequest } from "./compositionFingerprint.ts";
import {
  assertCompositionExecutionSnapshot,
  compositionExecutionProfile,
} from "./compositionExecutionPolicy.ts";
import { executeClaimedHistoryAnalysis } from "./claimedExecution.ts";
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
  captureCompositionOutcome,
} from "./execution.ts";
import {
  buildCompositionDraft,
  parseCompositionRequestStructure,
} from "./compositionAdmission.ts";

export type CompositionAnalysisWork = Omit<AnalysisWork, "provider_outcome"> & {
  provider_outcome?: unknown;
};

/** Snapshot the private service response before any await. No caller JSON can
 * supply a worker claim. Unknown dispatch cannot acquire execution authority. */
export function parseCompositionAnalysisWork(
  value: unknown,
  observation: string,
  analysis: string,
): CompositionAnalysisWork {
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
  const input = parseCompositionRequestStructure(row.input);
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
    q.provider !== "gemini" ||
    !["gemini_baseline_v1", "gemini_generation3_v1"].includes(
      String(q.binding),
    ) ||
    (q.binding === "gemini_generation3_v1" &&
      input.identification_protocol !== 7) ||
    q.processor_permission !== "google_gemini" ||
    q.input_profile !==
      compositionExecutionProfile(input).profile ||
    !["free", "pro"].includes(String(q.effective_tier)) ||
    q.model !==
      (q.binding === "gemini_generation3_v1"
        ? "gemini-3.8-flash"
        : q.effective_tier === "pro"
        ? "gemini-2.5-pro"
        : "gemini-2.5-flash") ||
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

/** Exactly one claimed V5 operation. Existing saved bytes, quota validation and
 * dispatch uncertainty protections remain owned by the V5 lane. */
export async function executeCompositionAnalysis(
  work: CompositionAnalysisWork,
  deps: AnalysisExecutionDependencies,
  signal?: AbortSignal,
): Promise<AnalysisState> {
  if (work.claimed) {
    // Received-result recovery skips media materialization, so validate the
    // saved typed digest before any draft, settlement or lease advance.
    const input = await validateCompositionRequest(work.input);
    work = { ...work, input };
  }
  return executeClaimedHistoryAnalysis(work, deps, {
    parseInput: parseCompositionRequestStructure,
    assertSnapshot: assertCompositionExecutionSnapshot,
    captureOutcome: captureCompositionOutcome,
    buildDraft: buildCompositionDraft,
  }, signal);
}
