import type { SupabaseClient } from "@supabase/supabase-js";
import { jsonResponse, logIdentitySafeError } from "../_shared/edgeHandler.ts";
import {
  AccountDeletionIntakeError,
  type AccountDeletionRequest,
  prepareAccountDeletionRecoveryV2,
  requestAccountDeletion,
  requestAccountDeletionV2,
} from "./db.ts";
import {
  type AccountDeletionWorkerResult,
  processAccountDeletionJobs,
} from "./worker.ts";

export type SafeDeleteHandlerDependencies = {
  request?: (
    userId: string,
    supabaseAdmin: SupabaseClient,
    recoverySecretHash: string | null,
  ) => Promise<
    {
      jobId: string;
      status: "pending" | "storage_pending" | "auth_pending" | "completed";
      manualProviderRevocationRequired: boolean;
      recoveryExpiresAt?: string | null;
    }
  >;
  prepareV2?: (
    userId: string,
    supabaseAdmin: SupabaseClient,
    recoverySecretHash: string,
    acknowledgementSecretHash: string,
  ) => Promise<{ prepared: true; recoveryExpiresAt: string }>;
  requestV2?: (
    userId: string,
    supabaseAdmin: SupabaseClient,
    recoverySecretHash: string,
  ) => Promise<AccountDeletionRequest>;
  process?: (
    supabaseAdmin: SupabaseClient,
    options: { limit: number; targetUserId: string },
  ) => Promise<AccountDeletionWorkerResult>;
};

export type SafeDeleteV2Operation =
  | {
    protocolVersion: 2;
    operation: "prepare";
    acknowledgementSecretHash: string;
  }
  | { protocolVersion: 2; operation: "commit" };

export async function handleSafeDelete(
  userId: string,
  supabaseAdmin: SupabaseClient,
  dependencies: SafeDeleteHandlerDependencies = {},
  recoverySecretHash: string | null = null,
  v2Operation: SafeDeleteV2Operation | null = null,
): Promise<Response> {
  if (v2Operation?.operation === "prepare") {
    if (recoverySecretHash === null) {
      throw new Error("Protocol-v2 preparation requires a recovery proof.");
    }
    const prepare = dependencies.prepareV2 ?? prepareAccountDeletionRecoveryV2;
    try {
      const preparation = await prepare(
        userId,
        supabaseAdmin,
        recoverySecretHash,
        v2Operation.acknowledgementSecretHash,
      );
      return jsonResponse(
        {
          success: true,
          status: "prepared",
          protocol_version: 2,
          recovery_capability_expires_at: preparation.recoveryExpiresAt,
        },
        200,
        { "Cache-Control": "private, no-store" },
      );
    } catch (error) {
      if (error instanceof AccountDeletionIntakeError) {
        return jsonResponse(
          { code: error.code, error: error.message },
          error.status,
          { "Cache-Control": "private, no-store" },
        );
      }
      throw error;
    }
  }

  const process = dependencies.process ?? processAccountDeletionJobs;

  // This durable write is the first mutation. If it fails, neither relational
  // cleanup nor Auth deletion is attempted.
  let deletion: AccountDeletionRequest;
  try {
    const requestedDeletion = v2Operation?.operation === "commit"
      ? await (dependencies.requestV2 ?? requestAccountDeletionV2)(
        userId,
        supabaseAdmin,
        recoverySecretHash ?? (() => {
          throw new Error("Protocol-v2 commit requires a recovery proof.");
        })(),
      )
      : await (dependencies.request ?? requestAccountDeletion)(
        userId,
        supabaseAdmin,
        recoverySecretHash,
      );
    deletion = {
      ...requestedDeletion,
      recoveryExpiresAt: requestedDeletion.recoveryExpiresAt ?? null,
    };
  } catch (error) {
    if (error instanceof AccountDeletionIntakeError) {
      return jsonResponse(
        { code: error.code, error: error.message },
        error.status,
        { "Cache-Control": "private, no-store" },
      );
    }
    throw error;
  }
  if (deletion.status === "completed") {
    return completedResponse(
      deletion.manualProviderRevocationRequired,
      deletion.recoveryExpiresAt ?? null,
      v2Operation === null ? null : 2,
    );
  }

  let result: AccountDeletionWorkerResult;
  try {
    result = await process(supabaseAdmin, {
      limit: 1,
      targetUserId: userId,
    });
  } catch {
    logIdentitySafeError("account_deletion_attempt_deferred", {
      operation: "delete_account",
      stage: "claim",
      code: "worker_start_failed",
    });
    return pendingResponse(
      deletion.manualProviderRevocationRequired,
      deletion.recoveryExpiresAt ?? null,
      v2Operation === null ? null : 2,
    );
  }

  if (result.completed > 0) {
    return completedResponse(
      deletion.manualProviderRevocationRequired,
      deletion.recoveryExpiresAt ?? null,
      v2Operation === null ? null : 2,
    );
  }

  for (const failure of result.failures) {
    logIdentitySafeError("account_deletion_attempt_deferred", {
      operation: "delete_account",
      stage: failure.stage,
      code: failure.code,
    });
  }

  return pendingResponse(
    deletion.manualProviderRevocationRequired,
    deletion.recoveryExpiresAt ?? null,
    v2Operation === null ? null : 2,
  );
}

function pendingResponse(
  manualProviderRevocationRequired: boolean,
  recoveryExpiresAt: string | null,
  protocolVersion: 2 | null = null,
): Response {
  return jsonResponse(
    {
      success: true,
      status: "pending",
      manual_provider_revocation_required: manualProviderRevocationRequired,
      ...(recoveryExpiresAt === null
        ? {}
        : { recovery_capability_expires_at: recoveryExpiresAt }),
      ...(protocolVersion === null
        ? {}
        : { protocol_version: protocolVersion }),
      message: "Account deletion was accepted and will continue automatically.",
    },
    202,
    { "Cache-Control": "private, no-store" },
  );
}

function completedResponse(
  manualProviderRevocationRequired: boolean,
  recoveryExpiresAt: string | null,
  protocolVersion: 2 | null = null,
): Response {
  return jsonResponse(
    {
      success: true,
      status: "completed",
      manual_provider_revocation_required: manualProviderRevocationRequired,
      ...(recoveryExpiresAt === null
        ? {}
        : { recovery_capability_expires_at: recoveryExpiresAt }),
      ...(protocolVersion === null
        ? {}
        : { protocol_version: protocolVersion }),
      message: "Account securely deleted and anonymized.",
    },
    200,
    { "Cache-Control": "private, no-store" },
  );
}
