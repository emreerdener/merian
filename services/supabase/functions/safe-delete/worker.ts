import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type AccountDeletionClaim,
  claimAccountDeletionJobs,
  completeAccountDeletionCleanup,
  deleteAuthProfile,
  finishAccountDeletionAttempt,
} from "./db.ts";

const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 100;

export type AccountDeletionWorkerResult = {
  claimed: number;
  completed: number;
  deferred: number;
  failures: Array<{
    jobId: string;
    stage: "cleanup" | "auth" | "completion";
    code: string;
  }>;
};

export type AccountDeletionWorkerDependencies = {
  claim?: (
    supabaseAdmin: SupabaseClient,
    limit: number,
    targetUserId?: string,
  ) => Promise<AccountDeletionClaim[]>;
  cleanup?: (
    supabaseAdmin: SupabaseClient,
    claim: AccountDeletionClaim,
  ) => Promise<void>;
  deleteAuth?: (
    userId: string,
    supabaseAdmin: SupabaseClient,
  ) => Promise<
    { succeeded: true } | { succeeded: false; errorCode: string }
  >;
  finish?: (
    supabaseAdmin: SupabaseClient,
    claim: AccountDeletionClaim,
    authDeleted: boolean,
    errorCode: string | null,
  ) => Promise<void>;
};

export async function processAccountDeletionJobs(
  supabaseAdmin: SupabaseClient,
  options: {
    limit?: number;
    targetUserId?: string;
  } = {},
  dependencies: AccountDeletionWorkerDependencies = {},
): Promise<AccountDeletionWorkerResult> {
  const limit = Math.min(
    Math.max(Math.trunc(options.limit ?? DEFAULT_LIMIT), 1),
    MAX_LIMIT,
  );
  const claimJobs = dependencies.claim ?? claimAccountDeletionJobs;
  const cleanup = dependencies.cleanup ?? completeAccountDeletionCleanup;
  const deleteAuth = dependencies.deleteAuth ?? deleteAuthProfile;
  const finish = dependencies.finish ?? finishAccountDeletionAttempt;
  const claims = await claimJobs(
    supabaseAdmin,
    limit,
    options.targetUserId,
  );
  const result: AccountDeletionWorkerResult = {
    claimed: claims.length,
    completed: 0,
    deferred: 0,
    failures: [],
  };

  for (const claim of claims) {
    let stage: "cleanup" | "auth" | "completion" = "cleanup";

    try {
      // Re-run the idempotent cleanup even for auth_pending retries. This
      // revalidates the database immediately before the external Auth delete
      // and removes any state written by an older rollout worker.
      await cleanup(supabaseAdmin, claim);

      stage = "auth";
      const authResult = await deleteAuth(claim.userId, supabaseAdmin);
      if (!authResult.succeeded) {
        await finish(
          supabaseAdmin,
          claim,
          false,
          authResult.errorCode,
        );
        recordDeferred(result, claim, "auth", authResult.errorCode);
        continue;
      }

      stage = "completion";
      await finish(supabaseAdmin, claim, true, null);
      result.completed += 1;
    } catch {
      const code = stage === "cleanup"
        ? "cleanup_failed"
        : stage === "auth"
        ? "auth_delete_failed"
        : "completion_write_failed";

      try {
        await finish(supabaseAdmin, claim, false, code);
      } catch {
        // The lease is durable. If this release write fails or a successful
        // completion response was lost, the database either already advanced
        // the job or a later worker safely reclaims it after lease expiry.
      }

      recordDeferred(result, claim, stage, code);
    }
  }

  return result;
}

function recordDeferred(
  result: AccountDeletionWorkerResult,
  claim: AccountDeletionClaim,
  stage: "cleanup" | "auth" | "completion",
  code: string,
): void {
  result.deferred += 1;
  result.failures.push({
    jobId: claim.jobId,
    stage,
    code,
  });
}
