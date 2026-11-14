import { assertGeminiLegacyDispatchOpen } from "./geminiProfiles.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { AIQuotaReservation } from "../aiQuota.ts";
import type { GeminiResponseReceipt } from "./geminiEnvelope.ts";

export interface GeminiTransportHooks {
  beforeTransport(): Promise<void>;
  recordResponse(receipt: GeminiResponseReceipt): Promise<void>;
  recordNonInvocation?(): Promise<void>;
  recordApplicationOutcome?(outcome: GeminiApplicationOutcome): Promise<void>;
}
export type GeminiApplicationOutcome = "success" | "refusal" | "error";

/** Validation happens after immutable provider evidence has been saved. */
export async function decodeGeminiApplication<T>(
  hooks: GeminiTransportHooks | undefined,
  decode: () => T,
  classify: (value: T) => GeminiApplicationOutcome = () => "success",
): Promise<T> {
  let value: T;
  try {
    value = decode();
  } catch (error) {
    await hooks?.recordApplicationOutcome?.("error");
    throw error;
  }
  // A lost outcome acknowledgement must not be relabelled as parser failure.
  await hooks?.recordApplicationOutcome?.(classify(value));
  return value;
}

export async function recordGeminiApplicationOutcome(
  client: SupabaseClient,
  receiptId: string,
  leaseToken: string,
  outcome: GeminiApplicationOutcome,
) {
  const { data, error } = await client.rpc(
    "record_gemini_application_outcome",
    {
      p_receipt_id: receiptId,
      p_lease_token: leaseToken,
      p_outcome: outcome,
    },
  ).retry(false).abortSignal(AbortSignal.timeout(5000));
  if (error || data !== true) {
    throw new Error("gemini_application_outcome_unavailable");
  }
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** A closure owned by one committed reservation, never a caller-selected model. */
export function geminiReservationTransport(
  client: SupabaseClient,
  userId: string,
  reservation: Pick<AIQuotaReservation, "id" | "leaseToken" | "attemptCount">,
): GeminiTransportHooks {
  let receiptId: string | null = null;
  let attempted = false;
  let responseSaved = false;
  async function recordNonInvocation() {
    const { data, error } = await client.rpc("record_gemini_non_invocation", {
      p_reservation_id: reservation.id,
      p_user_id: userId,
      p_lease_token: reservation.leaseToken,
      p_attempt_count: reservation.attemptCount,
      p_receipt_id: receiptId,
    }).retry(false).abortSignal(AbortSignal.timeout(5000));
    if (error || data !== true) {
      throw new Error("gemini_non_invocation_unavailable");
    }
  }
  return Object.freeze({
    recordNonInvocation,
    async beforeTransport() {
      if (attempted) throw new Error("gemini_transport_already_attempted");
      attempted = true;
      const { data, error } = await client.rpc("authorize_gemini_transport", {
        p_reservation_id: reservation.id,
        p_user_id: userId,
        p_lease_token: reservation.leaseToken,
        p_attempt_count: reservation.attemptCount,
      }).retry(false).abortSignal(AbortSignal.timeout(5000));
      // A lost acknowledgement is uncertainty, never permission or refund proof.
      if (error || typeof data !== "string" || !UUID.test(data)) {
        if (error?.message === "gemini_dispatch_closed") {
          // This live closure has not entered transport. SQL also requires no
          // other worker's witness before accepting its positive assertion.
          await recordNonInvocation().catch(() => {});
        }
        throw new Error("gemini_transport_unavailable");
      }
      receiptId = data;
    },
    async recordResponse(receipt: GeminiResponseReceipt) {
      if (!receiptId) throw new Error("gemini_transport_not_owned");
      const { data, error } = await client.rpc(
        "record_gemini_invocation_receipt",
        {
          p_receipt_id: receiptId,
          p_lease_token: reservation.leaseToken,
          p_receipt: receipt,
        },
      ).retry(false).abortSignal(AbortSignal.timeout(5000));
      if (error || data !== true) throw new Error("gemini_receipt_unavailable");
      responseSaved = true;
    },
    async recordApplicationOutcome(outcome: GeminiApplicationOutcome) {
      if (!responseSaved || !receiptId) return;
      await recordGeminiApplicationOutcome(
        client,
        receiptId,
        reservation.leaseToken,
        outcome,
      );
    },
  });
}

/** Background public-fact jobs have their own durable claim, never a fake user quota. */
export async function geminiSpeciesTransport(
  client: SupabaseClient,
  jobId: string,
  attempt: number,
) {
  const { data, error } = await client.rpc("read_gemini_species_execution", {
    p_job: jobId,
    p_attempt: attempt,
  })
    .retry(false).abortSignal(AbortSignal.timeout(5000));
  if (
    error || !data ||
    !["gemini-2.5-flash", "gemini-3.5-flash-lite"].includes(data.model) ||
    !UUID.test(data.owner_token)
  ) {
    throw new Error("gemini_species_not_owned");
  }
  const owner = data.owner_token as string;
  let attempted = false;
  const advance = async (action: string, receipt?: GeminiResponseReceipt) => {
    const { data, error } = await client.rpc(
      "advance_gemini_species_execution",
      {
        p_job: jobId,
        p_attempt: attempt,
        p_owner: owner,
        p_action: action,
        p_receipt: receipt ?? null,
      },
    ).retry(false).abortSignal(AbortSignal.timeout(5000));
    if (error || data !== true) {
      throw new Error("gemini_species_transition_unavailable");
    }
  };
  const transport: GeminiTransportHooks = {
    async beforeTransport() {
      if (attempted) throw new Error("gemini_transport_already_attempted");
      attempted = true;
      await advance("dispatch");
    },
    recordNonInvocation: () => advance("not_invoked"),
    async recordResponse(receipt) {
      await advance("receipt", receipt);
    },
  };
  return { model: data.model as string, transport };
}

/** The only local checks after the durable permit occur before any network call.
 * If this live owner knows it did not invoke, persist that fact; a crash cannot. */
export async function enterGeminiTransport(
  hooks: GeminiTransportHooks | undefined,
  model: string,
) {
  if (!hooks) throw new Error("gemini_transport_authority_required");
  await hooks.beforeTransport();
  try {
    assertGeminiLegacyDispatchOpen(model);
  } catch (error) {
    await hooks?.recordNonInvocation?.().catch(() => {});
    throw error;
  }
}
