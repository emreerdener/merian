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
    { jobId: string; status: "pending" | "auth_pending" | "completed" }
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
    return completedResponse();
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
    return pendingResponse();
  }

  if (result.completed > 0) {
    return completedResponse();
  }

  for (const failure of result.failures) {
    logStructuredError("account_deletion_attempt_deferred", {
      job_id: failure.jobId,
      stage: failure.stage,
      code: failure.code,
    });
  }

  return pendingResponse();
}

function pendingResponse(): Response {
  return jsonResponse(
    {
      success: true,
      status: "pending",
      message: "Account deletion was accepted and will continue automatically.",
    },
    202,
    { "Cache-Control": "private, no-store" },
  );
}

function completedResponse(): Response {
  return jsonResponse(
    {
      success: true,
      status: "completed",
      message: "Account securely deleted and anonymized.",
    },
    200,
    { "Cache-Control": "private, no-store" },
  );
}
