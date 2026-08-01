import {
  createClient,
  type PostgrestError,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { createDeadlineFetchTransport } from "../_shared/outbound.ts";
import { requirePublicApiKeyFromEnvironment } from "../_shared/publishableKey.ts";
import type { MergeProvider } from "./protocol.ts";

const SUPABASE_USER_REQUEST_TIMEOUT_MS = 30_000;

export type PreparedGhostMergeHandoff = {
  handoffId: string;
  expiresAt: string;
};

export type ConsumedGhostMergeHandoff = {
  handoffId: string;
  ghostUserId: string;
  targetUserId: string;
  alreadyMerged: boolean;
  mergedAt: string;
  authDeletedAt: string | null;
};

type HandoffRow = {
  handoff_id: string;
  expires_at: string;
};

type MergeReceiptRow = {
  handoff_id: string;
  ghost_user_id: string;
  target_user_id: string;
  already_merged: boolean;
  merged_at: string;
  auth_deleted_at: string | null;
};

export class GhostMergeDatabaseError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
    message: string,
    readonly internalMessage?: string,
  ) {
    super(message);
    this.name = "GhostMergeDatabaseError";
  }
}

export async function issueGhostMergeHandoff(
  req: Request,
  secretHash: string,
  provider: MergeProvider,
  providerSubject: string,
): Promise<PreparedGhostMergeHandoff> {
  const client = requestScopedClient(req);
  const { data, error } = await client
    .rpc("issue_ghost_profile_merge_handoff", {
      p_secret_hash: secretHash,
      p_expected_provider: provider,
      p_expected_provider_subject: providerSubject,
    })
    .single();

  if (error || !data) {
    throw mapDatabaseError(error, "Unable to prepare account upgrade.");
  }

  const row = data as HandoffRow;
  return {
    handoffId: row.handoff_id,
    expiresAt: row.expires_at,
  };
}

export async function consumeGhostMergeHandoff(
  req: Request,
  handoffId: string,
  secretHash: string,
): Promise<ConsumedGhostMergeHandoff> {
  const client = requestScopedClient(req);
  const { data, error } = await client
    .rpc("consume_ghost_profile_merge_handoff", {
      p_handoff_id: handoffId,
      p_secret_hash: secretHash,
    })
    .single();

  if (error || !data) {
    throw mapDatabaseError(error, "Unable to complete account upgrade.");
  }

  const row = data as MergeReceiptRow;
  return {
    handoffId: row.handoff_id,
    ghostUserId: row.ghost_user_id,
    targetUserId: row.target_user_id,
    alreadyMerged: row.already_merged,
    mergedAt: row.merged_at,
    authDeletedAt: row.auth_deleted_at,
  };
}

export async function recordGhostAuthCleanup(
  handoffId: string,
  succeeded: boolean,
  errorCode: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc(
    "record_ghost_profile_merge_auth_cleanup",
    {
      p_handoff_id: handoffId,
      p_succeeded: succeeded,
      p_error_code: errorCode,
    },
  );

  if (error) {
    throw new GhostMergeDatabaseError(
      "cleanup_receipt_failed",
      503,
      "Account data was upgraded, but cleanup confirmation is pending.",
      error.message,
    );
  }
}

export async function deleteMergedGhostAuthUser(
  ghostUserId: string,
  supabaseAdmin: SupabaseClient,
): Promise<
  { succeeded: true } | { succeeded: false; errorCode: string }
> {
  const { error } = await supabaseAdmin.auth.admin.deleteUser(ghostUserId);
  if (!error) return { succeeded: true };

  const status = typeof error.status === "number" ? error.status : null;
  if (
    status === 404 ||
    error.code === "user_not_found"
  ) {
    return { succeeded: true };
  }

  return {
    succeeded: false,
    errorCode: typeof error.code === "string"
      ? error.code
      : (status ? `auth_http_${status}` : "auth_delete_failed"),
  };
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
        fetch: createDeadlineFetchTransport(
          SUPABASE_USER_REQUEST_TIMEOUT_MS,
        ),
        headers: { Authorization: authorization },
      },
    },
  );
}

export function mapDatabaseError(
  error: PostgrestError | null,
  fallbackMessage: string,
): GhostMergeDatabaseError {
  const internalMessage = error?.message ?? "RPC returned no data.";
  const normalized = internalMessage.toLowerCase();

  if (normalized.includes("ghost_merge_handoff_expired")) {
    return new GhostMergeDatabaseError(
      "handoff_expired",
      410,
      "The account-upgrade proof expired. Please sign in again.",
      internalMessage,
    );
  }

  if (
    normalized.includes("ghost_merge_handoff_invalid") ||
    normalized.includes("ghost_merge_source_not_available")
  ) {
    return new GhostMergeDatabaseError(
      "handoff_invalid",
      404,
      "The account-upgrade proof is invalid or no longer available.",
      internalMessage,
    );
  }

  if (
    normalized.includes("ghost_merge_destination_identity_mismatch") ||
    normalized.includes("ghost_merge_destination_must") ||
    normalized.includes("ghost_merge_source_must_be_anonymous") ||
    normalized.includes("ghost_merge_authentication_required")
  ) {
    return new GhostMergeDatabaseError(
      "handoff_forbidden",
      403,
      "This session is not authorized to complete the account upgrade.",
      internalMessage,
    );
  }

  if (normalized.includes("ghost_merge_source_already_merged")) {
    return new GhostMergeDatabaseError(
      "source_already_merged",
      409,
      "This guest profile has already been upgraded.",
      internalMessage,
    );
  }

  if (
    normalized.includes("ghost_merge_schema_") ||
    normalized.includes("ghost_merge_unhandled_reference") ||
    normalized.includes("ghost_merge_unclassified_reference") ||
    normalized.includes("ghost_merge_stale_reference_policy") ||
    normalized.includes("ghost_merge_blocked_reference") ||
    normalized.includes("ghost_merge_preserved_reference_present") ||
    normalized.includes("ghost_merge_invalid_source_profile_policy") ||
    normalized.includes("ghost_merge_invalid_scan_species_policy") ||
    normalized.includes("ghost_merge_unknown_policy_handler") ||
    normalized.includes("ghost_merge_orchestrator_") ||
    normalized.includes("ghost_merge_species_ledger_mismatch")
  ) {
    return new GhostMergeDatabaseError(
      "merge_temporarily_unavailable",
      503,
      "Account upgrade is temporarily unavailable. Your guest data is unchanged.",
      internalMessage,
    );
  }

  if (error?.code === "23505") {
    return new GhostMergeDatabaseError(
      "merge_conflict",
      409,
      "Account upgrade is already in progress.",
      internalMessage,
    );
  }

  if (
    error?.code === "40001" ||
    error?.code === "40P01" ||
    error?.code === "55P03" ||
    error?.code === "57014"
  ) {
    return new GhostMergeDatabaseError(
      "merge_temporarily_unavailable",
      503,
      "Account upgrade is temporarily unavailable. Retrying is safe.",
      internalMessage,
    );
  }

  return new GhostMergeDatabaseError(
    "merge_failed",
    500,
    fallbackMessage,
    internalMessage,
  );
}
