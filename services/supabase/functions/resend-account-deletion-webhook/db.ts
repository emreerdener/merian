import type { SupabaseClient } from "@supabase/supabase-js";
import type { ResendAccountDeletionEvent } from "./protocol.ts";

export type ResendAccountDeletionEventOutcome =
  | "delivered"
  | "delivery_pending"
  | "retry_required"
  | "duplicate"
  | "ignored_unknown_attempt"
  | "ignored_stale_attempt";

export class ResendAccountDeletionDatabaseError extends Error {
  constructor(message: string, readonly code: string | null) {
    super(message);
    this.name = "ResendAccountDeletionDatabaseError";
  }
}

export async function recordResendAccountDeletionEvent(
  event: ResendAccountDeletionEvent,
  messageId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ResendAccountDeletionEventOutcome> {
  let response;
  try {
    response = await supabaseAdmin.rpc(
      "record_account_deletion_manual_revocation_event",
      {
        p_attempt_token: event.attemptId,
        p_provider_event_id: messageId,
        p_provider_delivery_id: event.emailId,
        p_event_type: event.type,
        p_provider_created_at: event.createdAt,
      },
    );
  } catch (error) {
    const detail = error instanceof Error ? error.message : "network failure";
    throw new ResendAccountDeletionDatabaseError(
      `Manual revocation event transaction failed: ${detail}`,
      null,
    );
  }

  const { data, error } = response;
  if (error) {
    throw new ResendAccountDeletionDatabaseError(
      `Manual revocation event transaction failed: ${error.message}`,
      typeof error.code === "string" ? error.code : null,
    );
  }
  if (!isOutcome(data)) {
    throw new ResendAccountDeletionDatabaseError(
      "Manual revocation event transaction returned invalid state.",
      null,
    );
  }
  return data;
}

function isOutcome(value: unknown): value is ResendAccountDeletionEventOutcome {
  return value === "delivered" ||
    value === "delivery_pending" ||
    value === "retry_required" ||
    value === "duplicate" ||
    value === "ignored_unknown_attempt" ||
    value === "ignored_stale_attempt";
}
