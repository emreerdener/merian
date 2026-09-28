/** Primary production accounting; evaluation adapters never use this owner. */
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type AIQuotaReservation,
  createAIProviderQuotaLease,
} from "../aiQuota.ts";
import { logStructuredError } from "../edgeHandler.ts";
import type { AIExecutionOutcome, PreparedAIExecution } from "./contracts.ts";
import { identificationProvenance } from "./provenance.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const count = (value: unknown): number | null =>
  typeof value === "number" && Number.isSafeInteger(value) && value >= 0 &&
    value <= 100_000_000
    ? value
    : null;

/** Only native counters cross this durable boundary, never generated content. */
export function identificationUsageFacts(result: AIExecutionOutcome) {
  const usage = result.usage;
  const breakdown: Record<string, Record<string, number>> = {};
  if (result.execution.provider === "gemini") {
    for (const category of ["prompt", "cached", "candidates", "tool"]) {
      const values = usage?.modalityBreakdown[category];
      const units: Record<string, number> = {};
      if (values && typeof values === "object" && !Array.isArray(values)) {
        for (const unit of ["text", "image", "audio", "video"]) {
          const value = count((values as Record<string, unknown>)[unit]);
          if (value !== null) units[unit] = value;
        }
      }
      breakdown[category] = units;
    }
  }
  return {
    modality_breakdown: breakdown,
    input_tokens: count(usage?.promptTokens),
    cached_tokens: count(usage?.cachedTokens),
    cache_write_tokens: count(usage?.cacheWriteTokens),
    output_tokens: count(usage?.outputTokens),
    candidate_tokens: count(usage?.candidateTokens),
    thinking_tokens: count(usage?.thinkingTokens),
    tool_tokens: count(usage?.toolTokens),
    total_tokens: count(usage?.totalTokens),
    service_tier: result.serviceTier === "default" ? "default" : null,
  };
}

export function prepareAccountedIdentification<
  Reservation extends AIQuotaReservation,
>(
  client: SupabaseClient,
  userId: string,
  reservation: Reservation,
  execution: PreparedAIExecution,
) {
  const provenance = identificationProvenance(execution.snapshot);
  let invocationId: string | null = null;
  let invoked = false;
  const lease = createAIProviderQuotaLease(
    client,
    userId,
    reservation,
    async () => {
      try {
        const { data, error } = await client.rpc(
          "commit_identification_invocation",
          {
            p_reservation_id: reservation.id,
            p_user_id: userId,
            p_lease_token: reservation.leaseToken,
            p_attempt_count: reservation.attemptCount,
            p_provenance: provenance,
          },
        ).abortSignal(AbortSignal.timeout(5_000));
        if (error || !Array.isArray(data) || data.length !== 1) return false;
        const row = data[0];
        if (
          !row || row.may_dispatch !== true ||
          typeof row.invocation_id !== "string" ||
          !UUID.test(row.invocation_id)
        ) return false;
        invocationId = row.invocation_id;
        return true;
      } catch {
        // An ambiguous commit is not permission to dispatch. Database ownership
        // remains authoritative and its outbox records unknown if it committed.
        return false;
      }
    },
  );
  async function report(result: AIExecutionOutcome | null): Promise<void> {
    try {
      const { data, error } = await client.rpc(
        "complete_identification_invocation",
        {
          p_invocation_id: invocationId,
          p_user_id: userId,
          p_lease_token: reservation.leaseToken,
          p_outcome: result?.kind ?? "unknown_execution",
          p_usage: result ? identificationUsageFacts(result) : {},
        },
      ).abortSignal(AbortSignal.timeout(5_000));
      if (error || typeof data !== "string" || !UUID.test(data)) {
        throw new Error("usage_report_unavailable");
      }
    } catch {
      // Persisted witness survives this worker. Reconciliation appends exactly
      // one unknown/unpriced event; accounting never causes a second model call.
      logStructuredError("identification_usage_report_unavailable", {});
    }
  }
  return {
    lease,
    async invoke(): Promise<AIExecutionOutcome> {
      if (!invocationId || invoked) {
        throw new Error("identification_invocation_not_owned");
      }
      invoked = true;
      let result: AIExecutionOutcome;
      try {
        result = await execution.invoke();
      } catch (error) {
        await report(null);
        throw error;
      }
      await report(result);
      return result;
    },
  };
}
