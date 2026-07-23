import { SupabaseClient } from "@supabase/supabase-js";

export interface RevenueCatStateSubject {
  kind: "customer" | "transfer_source" | "transfer_destination";
  candidateUserIds: string[];
  authoritativeSnapshotAtMs: number;
  targetTier: "free" | "pro";
  targetExpiresAt: string | null;
}

export interface RevenueCatStateTransition {
  eventId: string;
  eventTimestampMs: number;
  eventType: string;
  payloadSha256: string;
  signatureTimestampSeconds: number;
  subjects: RevenueCatStateSubject[];
}

export interface RevenueCatStateResult {
  outcome: "applied" | "duplicate" | "ignored" | "mixed" | "stale";
  subjectCount: number;
  appliedCount: number;
  staleCount: number;
}

export class RevenueCatDatabaseError extends Error {
  constructor(message: string, readonly code: string | null) {
    super(message);
    this.name = "RevenueCatDatabaseError";
  }
}

interface RevenueCatRpcRow {
  outcome?: unknown;
  subject_count?: unknown;
  applied_count?: unknown;
  stale_count?: unknown;
}

function parseRevenueCatRpcRow(
  row: RevenueCatRpcRow | undefined,
): RevenueCatStateResult {
  if (
    !row ||
    !["applied", "duplicate", "ignored", "mixed", "stale"].includes(
      String(row.outcome),
    ) ||
    typeof row.subject_count !== "number" ||
    !Number.isSafeInteger(row.subject_count) ||
    row.subject_count < 0 ||
    typeof row.applied_count !== "number" ||
    !Number.isSafeInteger(row.applied_count) ||
    row.applied_count < 0 ||
    typeof row.stale_count !== "number" ||
    !Number.isSafeInteger(row.stale_count) ||
    row.stale_count < 0 ||
    row.applied_count + row.stale_count !== row.subject_count
  ) {
    throw new RevenueCatDatabaseError(
      "RevenueCat state transaction returned an invalid response.",
      null,
    );
  }

  return {
    outcome: row.outcome as RevenueCatStateResult["outcome"],
    subjectCount: row.subject_count,
    appliedCount: row.applied_count,
    staleCount: row.stale_count,
  };
}

export async function getRevenueCatWebhookEventResult(
  eventId: string,
  eventTimestampMs: number,
  eventType: string,
  payloadSha256: string,
  supabaseAdmin: SupabaseClient,
): Promise<RevenueCatStateResult | null> {
  let response;
  try {
    response = await supabaseAdmin.rpc(
      "get_revenuecat_webhook_event_result",
      {
        p_event_id: eventId,
        p_event_timestamp_ms: eventTimestampMs,
        p_event_type: eventType,
        p_payload_sha256: payloadSha256,
      },
    );
  } catch (error) {
    const detail = error instanceof Error ? error.message : "network failure";
    throw new RevenueCatDatabaseError(
      `RevenueCat event lookup failed: ${detail}`,
      null,
    );
  }

  const { data, error } = response;
  if (error) {
    throw new RevenueCatDatabaseError(
      `RevenueCat event lookup failed: ${error.message}`,
      typeof error.code === "string" ? error.code : null,
    );
  }

  if (!Array.isArray(data) || data.length === 0) return null;
  return parseRevenueCatRpcRow(data[0] as RevenueCatRpcRow);
}

export async function applyRevenueCatCustomerState(
  transition: RevenueCatStateTransition,
  supabaseAdmin: SupabaseClient,
): Promise<RevenueCatStateResult> {
  let response;
  try {
    response = await supabaseAdmin.rpc(
      "apply_revenuecat_customer_state",
      {
        p_event_id: transition.eventId,
        p_event_timestamp_ms: transition.eventTimestampMs,
        p_event_type: transition.eventType,
        p_payload_sha256: transition.payloadSha256,
        p_signature_timestamp_s: transition.signatureTimestampSeconds,
        p_subjects: transition.subjects.map((subject) => ({
          subject_kind: subject.kind,
          candidate_user_ids: subject.candidateUserIds,
          authoritative_snapshot_at_ms: subject.authoritativeSnapshotAtMs,
          target_tier: subject.targetTier,
          target_expires_at: subject.targetExpiresAt,
        })),
      },
    );
  } catch (error) {
    const detail = error instanceof Error ? error.message : "network failure";
    throw new RevenueCatDatabaseError(
      `RevenueCat state transaction failed: ${detail}`,
      null,
    );
  }
  const { data, error } = response;

  if (error) {
    throw new RevenueCatDatabaseError(
      `RevenueCat state transaction failed: ${error.message}`,
      typeof error.code === "string" ? error.code : null,
    );
  }

  const row = Array.isArray(data)
    ? data[0] as RevenueCatRpcRow | undefined
    : null;
  return parseRevenueCatRpcRow(row ?? undefined);
}
