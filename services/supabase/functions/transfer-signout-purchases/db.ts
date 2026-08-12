import {
  createClient,
  type PostgrestError,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { createDeadlineFetchTransport } from "../_shared/outbound.ts";
import { requirePublicApiKeyFromEnvironment } from "../_shared/publishableKey.ts";
import type { RevenueCatEntitlementState } from "../revenuecat-webhook/subscriber.ts";

const USER_REQUEST_TIMEOUT_MS = 30_000;

export type PreparedSignoutPurchaseHandoff = {
  handoffId: string;
  expiresAt: string;
};

export type BoundSignoutPurchaseHandoff = {
  handoffId: string;
  sourceUserId: string;
  destinationUserId: string;
  sourceSnapshotAtMs: number;
  expectedStoreAccess: RevenueCatEntitlementState;
  status: "bound" | "completed";
  destinationVerifiedSnapshotAtMs: number | null;
  destinationVerifiedStoreAccess: RevenueCatEntitlementState | null;
  boundAt: string;
  alreadyBound: boolean;
};

export type CompletedSignoutPurchaseHandoff = {
  handoffId: string;
  completedAt: string;
  alreadyCompleted: boolean;
};

export type CancelledSignoutPurchaseHandoff = {
  handoffId: string;
  cancelledAt: string;
  alreadyCancelled: boolean;
};

export type SignoutPurchaseSourceEntitlement = RevenueCatEntitlementState;

type PreparedRow = {
  handoff_id?: unknown;
  expires_at?: unknown;
};

type BoundRow = {
  handoff_id?: unknown;
  source_user_id?: unknown;
  destination_user_id?: unknown;
  source_snapshot_at_ms?: unknown;
  expected_store_tier?: unknown;
  expected_store_expires_at?: unknown;
  handoff_status?: unknown;
  destination_verified_snapshot_at_ms?: unknown;
  destination_verified_store_tier?: unknown;
  destination_verified_store_expires_at?: unknown;
  bound_at?: unknown;
  already_bound?: unknown;
};

type CompletedRow = {
  handoff_id?: unknown;
  completed_at?: unknown;
  already_completed?: unknown;
};

type CancelledRow = {
  handoff_id?: unknown;
  cancelled_at?: unknown;
  already_cancelled?: unknown;
};

export class SignoutPurchaseHandoffDatabaseError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
    message: string,
    readonly internalMessage?: string,
  ) {
    super(message);
    this.name = "SignoutPurchaseHandoffDatabaseError";
  }
}

export async function issueSignoutPurchaseHandoff(
  supabaseAdmin: SupabaseClient,
  sourceUserId: string,
  secretHash: string,
  sourceSnapshotAtMs: number,
  expectedStoreAccess: RevenueCatEntitlementState,
): Promise<PreparedSignoutPurchaseHandoff> {
  const { data, error } = await supabaseAdmin.rpc(
    "issue_signout_purchase_handoff",
    {
      p_source_user_id: sourceUserId,
      p_secret_hash: secretHash,
      p_source_snapshot_at_ms: sourceSnapshotAtMs,
      p_expected_store_tier: expectedStoreAccess.targetTier,
      p_expected_store_expires_at: expectedStoreAccess.expiresAt,
    },
  );
  const row = singleRow<PreparedRow>(
    data,
    error,
    "Unable to prepare sign-out.",
  );
  return {
    handoffId: requiredString(row.handoff_id, "handoff_id"),
    expiresAt: requiredTimestamp(row.expires_at, "expires_at"),
  };
}

/** Reads the durable server projection used to fence stale StoreKit history. */
export async function readSignoutPurchaseSourceEntitlement(
  supabaseAdmin: SupabaseClient,
  sourceUserId: string,
): Promise<SignoutPurchaseSourceEntitlement> {
  const { data, error } = await supabaseAdmin
    .from("users")
    .select("subscription_tier,subscription_expires_at")
    .eq("id", sourceUserId)
    .limit(1);
  if (error || !Array.isArray(data) || data.length !== 1) {
    throw new SignoutPurchaseHandoffDatabaseError(
      "handoff_source_entitlement_unavailable",
      503,
      "Purchase continuity is temporarily unavailable. Please try again.",
      error?.message ?? "Source entitlement projection was unavailable.",
    );
  }
  const row = data[0] as Record<string, unknown>;
  const tier = row.subscription_tier;
  if (tier !== "free" && tier !== "pro") {
    throw invalidDatabaseResponse("subscription_tier");
  }
  const expiresAt = row.subscription_expires_at === null
    ? null
    : requiredTimestamp(
      row.subscription_expires_at,
      "subscription_expires_at",
    );
  if (tier === "free" && expiresAt !== null) {
    throw invalidDatabaseResponse("subscription_expires_at");
  }
  return { targetTier: tier, expiresAt };
}

export async function bindSignoutPurchaseHandoff(
  req: Request,
  handoffId: string,
  secretHash: string,
): Promise<BoundSignoutPurchaseHandoff> {
  const client = requestScopedClient(req);
  const { data, error } = await client.rpc(
    "bind_signout_purchase_handoff",
    { p_handoff_id: handoffId, p_secret_hash: secretHash },
  );
  const row = singleRow<BoundRow>(
    data,
    error,
    "Unable to bind sign-out purchase continuity.",
  );
  const tier = row.expected_store_tier;
  if (tier !== "free" && tier !== "pro") {
    throw invalidDatabaseResponse("expected_store_tier");
  }
  const expiresAt = row.expected_store_expires_at === null
    ? null
    : requiredTimestamp(
      row.expected_store_expires_at,
      "expected_store_expires_at",
    );
  const sourceSnapshotAtMs = row.source_snapshot_at_ms;
  if (
    typeof sourceSnapshotAtMs !== "number" ||
    !Number.isSafeInteger(sourceSnapshotAtMs) ||
    sourceSnapshotAtMs < 0
  ) {
    throw invalidDatabaseResponse("source_snapshot_at_ms");
  }
  if (typeof row.already_bound !== "boolean") {
    throw invalidDatabaseResponse("already_bound");
  }
  if (row.handoff_status !== "bound" && row.handoff_status !== "completed") {
    throw invalidDatabaseResponse("handoff_status");
  }
  const destinationVerifiedSnapshotAtMs = row
      .destination_verified_snapshot_at_ms === null
    ? null
    : requiredSnapshot(
      row.destination_verified_snapshot_at_ms,
      "destination_verified_snapshot_at_ms",
    );
  const destinationVerifiedStoreAccess = parseOptionalStoreAccess(
    row.destination_verified_store_tier,
    row.destination_verified_store_expires_at,
    destinationVerifiedSnapshotAtMs,
  );
  if (
    (row.handoff_status === "bound" &&
      (destinationVerifiedSnapshotAtMs !== null ||
        destinationVerifiedStoreAccess !== null)) ||
    (row.handoff_status === "completed" &&
      (destinationVerifiedSnapshotAtMs === null ||
        destinationVerifiedStoreAccess === null))
  ) {
    throw invalidDatabaseResponse("destination_verified_store_access");
  }
  return {
    handoffId: requiredString(row.handoff_id, "handoff_id"),
    sourceUserId: requiredString(row.source_user_id, "source_user_id"),
    destinationUserId: requiredString(
      row.destination_user_id,
      "destination_user_id",
    ),
    sourceSnapshotAtMs,
    expectedStoreAccess: { targetTier: tier, expiresAt },
    status: row.handoff_status,
    destinationVerifiedSnapshotAtMs,
    destinationVerifiedStoreAccess,
    boundAt: requiredTimestamp(row.bound_at, "bound_at"),
    alreadyBound: row.already_bound,
  };
}

export async function cancelSignoutPurchaseHandoff(
  req: Request,
  handoffId: string,
  secretHash: string,
): Promise<CancelledSignoutPurchaseHandoff> {
  const client = requestScopedClient(req);
  const { data, error } = await client.rpc(
    "cancel_signout_purchase_handoff",
    { p_handoff_id: handoffId, p_secret_hash: secretHash },
  );
  const row = singleRow<CancelledRow>(
    data,
    error,
    "Unable to cancel sign-out purchase continuity.",
  );
  if (typeof row.already_cancelled !== "boolean") {
    throw invalidDatabaseResponse("already_cancelled");
  }
  return {
    handoffId: requiredString(row.handoff_id, "handoff_id"),
    cancelledAt: requiredTimestamp(row.cancelled_at, "cancelled_at"),
    alreadyCancelled: row.already_cancelled,
  };
}

export async function completeSignoutPurchaseHandoff(
  supabaseAdmin: SupabaseClient,
  handoffId: string,
  secretHash: string,
  destinationUserId: string,
  destinationSnapshotAtMs: number,
  destinationStoreAccess: RevenueCatEntitlementState,
): Promise<CompletedSignoutPurchaseHandoff> {
  const { data, error } = await supabaseAdmin.rpc(
    "complete_signout_purchase_handoff",
    {
      p_handoff_id: handoffId,
      p_secret_hash: secretHash,
      p_destination_user_id: destinationUserId,
      p_destination_snapshot_at_ms: destinationSnapshotAtMs,
      p_destination_store_tier: destinationStoreAccess.targetTier,
      p_destination_store_expires_at: destinationStoreAccess.expiresAt,
    },
  );
  const row = singleRow<CompletedRow>(
    data,
    error,
    "Unable to complete sign-out purchase continuity.",
  );
  if (typeof row.already_completed !== "boolean") {
    throw invalidDatabaseResponse("already_completed");
  }
  return {
    handoffId: requiredString(row.handoff_id, "handoff_id"),
    completedAt: requiredTimestamp(row.completed_at, "completed_at"),
    alreadyCompleted: row.already_completed,
  };
}

function parseOptionalStoreAccess(
  tier: unknown,
  expiresAtValue: unknown,
  snapshotAtMs: number | null,
): RevenueCatEntitlementState | null {
  if (tier === null && expiresAtValue === null) return null;
  if ((tier !== "free" && tier !== "pro") || snapshotAtMs === null) {
    throw invalidDatabaseResponse("destination_verified_store_tier");
  }
  const expiresAt = expiresAtValue === null ? null : requiredTimestamp(
    expiresAtValue,
    "destination_verified_store_expires_at",
  );
  if (
    (tier === "free" && expiresAt !== null) ||
    (expiresAt !== null && Date.parse(expiresAt) <= snapshotAtMs)
  ) {
    throw invalidDatabaseResponse("destination_verified_store_expires_at");
  }
  return { targetTier: tier, expiresAt };
}

function requestScopedClient(req: Request): SupabaseClient {
  const authorization = req.headers.get("Authorization") ?? "";
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    requirePublicApiKeyFromEnvironment(),
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
      global: {
        fetch: createDeadlineFetchTransport(USER_REQUEST_TIMEOUT_MS),
        headers: { Authorization: authorization },
      },
    },
  );
}

function singleRow<T>(
  data: unknown,
  error: PostgrestError | null,
  fallbackMessage: string,
): T {
  if (error || !Array.isArray(data) || data.length !== 1) {
    throw mapDatabaseError(error, fallbackMessage);
  }
  return data[0] as T;
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw invalidDatabaseResponse(field);
  }
  return value;
}

function requiredTimestamp(value: unknown, field: string): string {
  const timestamp = requiredString(value, field);
  if (!Number.isFinite(Date.parse(timestamp))) {
    throw invalidDatabaseResponse(field);
  }
  return timestamp;
}

function requiredSnapshot(value: unknown, field: string): number {
  if (
    typeof value !== "number" || !Number.isSafeInteger(value) || value < 0
  ) {
    throw invalidDatabaseResponse(field);
  }
  return value;
}

function invalidDatabaseResponse(
  field: string,
): SignoutPurchaseHandoffDatabaseError {
  return new SignoutPurchaseHandoffDatabaseError(
    "handoff_invalid_response",
    503,
    "Purchase continuity is temporarily unavailable. Retrying is safe.",
    `RPC returned invalid ${field}.`,
  );
}

export function mapDatabaseError(
  error: PostgrestError | null,
  fallbackMessage: string,
): SignoutPurchaseHandoffDatabaseError {
  const internalMessage = error?.message ?? "RPC returned no data.";
  const normalized = internalMessage.toLowerCase();

  if (normalized.includes("signout_handoff_expired")) {
    return new SignoutPurchaseHandoffDatabaseError(
      "handoff_expired",
      410,
      "The sign-out proof expired. Sign in and try again.",
      internalMessage,
    );
  }
  if (
    normalized.includes("signout_handoff_invalid") ||
    normalized.includes("signout_handoff_source_not_available") ||
    normalized.includes("signout_handoff_destination_not_available") ||
    normalized.includes(
      "signout_handoff_fresh_anonymous_destination_required",
    ) ||
    normalized.includes("signout_handoff_profile_not_available")
  ) {
    return new SignoutPurchaseHandoffDatabaseError(
      "handoff_invalid",
      404,
      "The sign-out proof is invalid or no longer available.",
      internalMessage,
    );
  }
  if (
    normalized.includes("signout_handoff_not_cancelable") ||
    normalized.includes("signout_handoff_already_bound")
  ) {
    return new SignoutPurchaseHandoffDatabaseError(
      "handoff_not_cancelable",
      409,
      "Purchase continuity is already bound to the signed-out account.",
      internalMessage,
    );
  }
  if (
    normalized.includes("signout_handoff_linked_source_required") ||
    normalized.includes("signout_handoff_anonymous_destination_required") ||
    normalized.includes("signout_handoff_authentication_required")
  ) {
    return new SignoutPurchaseHandoffDatabaseError(
      "handoff_forbidden",
      403,
      "This session is not authorized for the sign-out purchase handoff.",
      internalMessage,
    );
  }
  if (
    error?.code === "40001" ||
    error?.code === "40P01" ||
    error?.code === "55P03" ||
    error?.code === "57014" ||
    normalized.includes("signout_handoff_not_bound")
  ) {
    return new SignoutPurchaseHandoffDatabaseError(
      "handoff_temporarily_unavailable",
      503,
      "Purchase continuity is temporarily unavailable. Retrying is safe.",
      internalMessage,
    );
  }
  return new SignoutPurchaseHandoffDatabaseError(
    "handoff_failed",
    500,
    fallbackMessage,
    internalMessage,
  );
}
