import type { SupabaseClient } from "@supabase/supabase-js";
import {
  initialAbortable,
  initialDeadline,
} from "../initialAnalysis/transport.ts";
import { parseInitialEvidenceEnvelopeV1 } from "../identify/initialEvidenceEnvelopeV1.ts";
import { HistoryError, invalidHistory } from "./contract.ts";
import {
  initialCapturePlanValue,
  parseInitialEvidenceCapturePlan,
} from "./initialEvidenceCapturePlan.ts";

/** Exact sealed recovery runs before admission, whose completed stop must stay
 * closed. SQL compares the entire plan to the retained immutable V9 manifest. */
export async function recoverPrivateCaptureCompletion(
  client: SupabaseClient,
  owner: string,
  candidate: unknown,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const plan = parseInitialEvidenceCapturePlan(owner, candidate);
  const response = await initialDeadline(
    signal,
    5_000,
    (current) =>
      initialAbortable(
        current,
        () =>
          client.rpc("recover_private_capture_completion", {
            p_owner: owner,
            p_plan: initialCapturePlanValue(plan),
          }).abortSignal(current),
      ),
  );
  if (response.error) {
    throw new HistoryError(
      response.error.message === "analysis_history_operation_conflict"
        ? "analysis_history_operation_conflict"
        : "analysis_history_unavailable",
    );
  }
  if (response.data === null) return null;
  const envelope = parseInitialEvidenceEnvelopeV1(response.data);
  const proof = envelope.initial_evidence;
  if (
    !proof || proof.owner_id !== owner || proof.scan_id !== plan.scanID ||
    proof.generation !== plan.generation
  ) return invalidHistory();
  return envelope;
}
