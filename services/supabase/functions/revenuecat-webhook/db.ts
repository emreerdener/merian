import { SupabaseClient } from "@supabase/supabase-js";

export interface RevenueCatStateSubject {
  kind: "customer" | "transfer_source" | "transfer_destination";
  lookupAppUserId: string;
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

export interface RevenueCatReconciliationSubject {
  kind: RevenueCatStateSubject["kind"];
  lookupAppUserId: string;
  candidateUserIds: string[];
}

export type RevenueCatIdentityKind = "legacy_user" | "purchase_principal";

export interface ResolvedRevenueCatIdentitySubject {
  position: number;
  kind: RevenueCatStateSubject["kind"];
  lookupAppUserId: string;
  identityKind: RevenueCatIdentityKind;
  identityId: string;
  allowNonSubscriptionPassGrant: boolean | null;
}

export interface RevenueCatIdentityStateSubject
  extends ResolvedRevenueCatIdentitySubject {
  authoritativeSnapshotAtMs: number;
  targetStoreTier: "free" | "pro";
  targetStoreExpiresAt: string | null;
  targetAccountGrantTier: "free" | "pro";
  targetAccountGrantExpiresAt: string | null;
  passGrantPolicyUpdate: boolean | null;
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

interface ResolvedIdentityRow {
  subject_position?: unknown;
  subject_kind?: unknown;
  lookup_app_user_id?: unknown;
  identity_kind?: unknown;
  identity_id?: unknown;
  allow_non_subscription_pass_grant?: unknown;
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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

export async function resolveRevenueCatIdentitySubjects(
  subjects: Array<{
    kind: RevenueCatStateSubject["kind"];
    identifiers: string[];
  }>,
  supabaseAdmin: SupabaseClient,
): Promise<ResolvedRevenueCatIdentitySubject[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "resolve_revenuecat_identity_subjects",
    {
      p_subjects: subjects.map((subject) => ({
        subject_kind: subject.kind,
        identifiers: subject.identifiers,
      })),
    },
  );
  if (error) {
    throw new RevenueCatDatabaseError(
      `RevenueCat identity resolution failed: ${error.message}`,
      typeof error.code === "string" ? error.code : null,
    );
  }
  if (!Array.isArray(data) || data.length > subjects.length) {
    throw new RevenueCatDatabaseError(
      "RevenueCat identity resolution returned an invalid response.",
      null,
    );
  }

  const seenPositions = new Set<number>();
  return data.map((value) => {
    const row = value as ResolvedIdentityRow;
    const position = row.subject_position;
    const kind = row.subject_kind;
    const lookupAppUserId = row.lookup_app_user_id;
    const identityKind = row.identity_kind;
    const identityId = row.identity_id;
    const allowNonSubscriptionPassGrant = row.allow_non_subscription_pass_grant;
    if (
      typeof position !== "number" || !Number.isSafeInteger(position) ||
      position < 1 || position > subjects.length ||
      seenPositions.has(position) || kind !== subjects[position - 1].kind ||
      typeof lookupAppUserId !== "string" || lookupAppUserId.length < 1 ||
      lookupAppUserId.length > 255 ||
      (identityKind !== "legacy_user" &&
        identityKind !== "purchase_principal") ||
      typeof identityId !== "string" || !UUID_RE.test(identityId) ||
      (identityKind === "legacy_user" &&
        allowNonSubscriptionPassGrant !== null) ||
      (identityKind === "purchase_principal" &&
        typeof allowNonSubscriptionPassGrant !== "boolean")
    ) {
      throw new RevenueCatDatabaseError(
        "RevenueCat identity resolution returned an invalid row.",
        null,
      );
    }
    seenPositions.add(position);
    return {
      position,
      kind: kind as ResolvedRevenueCatIdentitySubject["kind"],
      lookupAppUserId,
      identityKind,
      identityId: identityId.toLowerCase(),
      allowNonSubscriptionPassGrant: identityKind === "purchase_principal"
        ? allowNonSubscriptionPassGrant as boolean
        : null,
    };
  });
}

export async function applyRevenueCatIdentityState(
  transition: Omit<RevenueCatStateTransition, "subjects"> & {
    subjects: RevenueCatIdentityStateSubject[];
  },
  supabaseAdmin: SupabaseClient,
): Promise<RevenueCatStateResult> {
  const { data, error } = await supabaseAdmin.rpc(
    "apply_revenuecat_identity_state",
    {
      p_event_id: transition.eventId,
      p_event_timestamp_ms: transition.eventTimestampMs,
      p_event_type: transition.eventType,
      p_payload_sha256: transition.payloadSha256,
      p_signature_timestamp_s: transition.signatureTimestampSeconds,
      p_subjects: transition.subjects.map((subject) => ({
        subject_kind: subject.kind,
        lookup_app_user_id: subject.lookupAppUserId,
        identity_kind: subject.identityKind,
        identity_id: subject.identityId,
        authoritative_snapshot_at_ms: subject.authoritativeSnapshotAtMs,
        target_store_tier: subject.targetStoreTier,
        target_store_expires_at: subject.targetStoreExpiresAt,
        target_account_grant_tier: subject.targetAccountGrantTier,
        target_account_grant_expires_at: subject.targetAccountGrantExpiresAt,
        allow_non_subscription_pass_grant: subject.passGrantPolicyUpdate,
      })),
    },
  );
  if (error) {
    throw new RevenueCatDatabaseError(
      `RevenueCat identity state transaction failed: ${error.message}`,
      typeof error.code === "string" ? error.code : null,
    );
  }
  const row = Array.isArray(data)
    ? data[0] as RevenueCatRpcRow | undefined
    : undefined;
  return parseRevenueCatRpcRow(row);
}

export async function scheduleRevenueCatIdentityReconciliation(
  subjects: ResolvedRevenueCatIdentitySubject[],
  supabaseAdmin: SupabaseClient,
): Promise<number> {
  const { data, error } = await supabaseAdmin.rpc(
    "schedule_revenuecat_identity_reconciliation",
    {
      p_subjects: subjects.map((subject) => ({
        subject_kind: subject.kind,
        lookup_app_user_id: subject.lookupAppUserId,
        identity_kind: subject.identityKind,
        identity_id: subject.identityId,
      })),
    },
  );
  if (error) {
    throw new RevenueCatDatabaseError(
      `RevenueCat identity reconciliation scheduling failed: ${error.message}`,
      typeof error.code === "string" ? error.code : null,
    );
  }
  if (
    typeof data !== "number" || !Number.isSafeInteger(data) || data < 0 ||
    data > subjects.length
  ) {
    throw new RevenueCatDatabaseError(
      "RevenueCat identity reconciliation scheduling returned an invalid response.",
      null,
    );
  }
  return data;
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
          lookup_app_user_id: subject.lookupAppUserId,
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

export async function scheduleRevenueCatReconciliation(
  subjects: RevenueCatReconciliationSubject[],
  supabaseAdmin: SupabaseClient,
): Promise<number> {
  let response;
  try {
    response = await supabaseAdmin.rpc(
      "schedule_revenuecat_reconciliation",
      {
        p_subjects: subjects.map((subject) => ({
          subject_kind: subject.kind,
          lookup_app_user_id: subject.lookupAppUserId,
          candidate_user_ids: subject.candidateUserIds,
        })),
      },
    );
  } catch (error) {
    const detail = error instanceof Error ? error.message : "network failure";
    throw new RevenueCatDatabaseError(
      `RevenueCat reconciliation scheduling failed: ${detail}`,
      null,
    );
  }

  const { data, error } = response;
  if (error) {
    throw new RevenueCatDatabaseError(
      `RevenueCat reconciliation scheduling failed: ${error.message}`,
      typeof error.code === "string" ? error.code : null,
    );
  }
  if (
    typeof data !== "number" ||
    !Number.isSafeInteger(data) ||
    data < 0 ||
    data > subjects.length
  ) {
    throw new RevenueCatDatabaseError(
      "RevenueCat reconciliation scheduling returned an invalid response.",
      null,
    );
  }
  return data;
}
