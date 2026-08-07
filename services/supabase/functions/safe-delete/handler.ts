import type { SupabaseClient } from "@supabase/supabase-js";
import { jsonResponse, logStructuredError } from "../_shared/edgeHandler.ts";
import { requestAccountDeletion } from "./db.ts";
import {
  type AccountDeletionWorkerResult,
  processAccountDeletionJobs,
} from "./worker.ts";

export type SafeDeleteHandlerDependencies = {
  request?: (
    userId: string,
    supabaseAdmin: SupabaseClient,
  ) => Promise<
    {
      jobId: string;
      status: "pending" | "storage_pending" | "auth_pending" | "completed";
      manualProviderRevocationRequired: boolean;
    }
  >;
  process?: (
    supabaseAdmin: SupabaseClient,
    options: { limit: number; targetUserId: string },
  ) => Promise<AccountDeletionWorkerResult>;
};

export async function handleSafeDelete(
  userId: string,
  supabaseAdmin: SupabaseClient,
  dependencies: SafeDeleteHandlerDependencies = {},
): Promise<Response> {
  const request = dependencies.request ?? requestAccountDeletion;
  const process = dependencies.process ?? processAccountDeletionJobs;

  // This durable write is the first mutation. If it fails, neither relational
  // cleanup nor Auth deletion is attempted.
  const deletion = await request(userId, supabaseAdmin);
  if (deletion.status === "completed") {
    return completedResponse(deletion.manualProviderRevocationRequired);
  }

  let result: AccountDeletionWorkerResult;
  try {
    result = await process(supabaseAdmin, {
      limit: 1,
      targetUserId: userId,
    });
  } catch {
    logStructuredError("account_deletion_attempt_deferred", {
      job_id: deletion.jobId,
      stage: "claim",
      code: "worker_start_failed",
    });
    return pendingResponse(deletion.manualProviderRevocationRequired);
  }

  if (result.completed > 0) {
    return completedResponse(deletion.manualProviderRevocationRequired);
  }

  for (const failure of result.failures) {
    logStructuredError("account_deletion_attempt_deferred", {
      job_id: failure.jobId,
      stage: failure.stage,
      code: failure.code,
    });
  }

  return pendingResponse(deletion.manualProviderRevocationRequired);
}

function pendingResponse(manualProviderRevocationRequired: boolean): Response {
  return jsonResponse(
    {
      success: true,
      status: "pending",
      manual_provider_revocation_required: manualProviderRevocationRequired,
      message: "Account deletion was accepted and will continue automatically.",
    },
    202,
    { "Cache-Control": "private, no-store" },
  );
}

function completedResponse(
  manualProviderRevocationRequired: boolean,
): Response {
  return jsonResponse(
    {
      success: true,
      status: "completed",
      manual_provider_revocation_required: manualProviderRevocationRequired,
      message: "Account securely deleted and anonymized.",
    },
    200,
    { "Cache-Control": "private, no-store" },
  );
}
