import type { SupabaseClient } from "@supabase/supabase-js";

export type AccountDeletionStatus =
  | "pending"
  | "storage_pending"
  | "auth_pending"
  | "completed";

export type AccountDeletionCleanupPhase =
  | "storage_pending"
  | "auth_pending";

export type AccountDeletionRequest = {
  jobId: string;
  status: AccountDeletionStatus;
};

export type AccountDeletionClaim = {
  jobId: string;
  userId: string;
  status: Exclude<AccountDeletionStatus, "completed">;
  claimToken: string;
  claimExpiresAt: string;
};

export type AuthDeletionResult =
  | { succeeded: true }
  | { succeeded: false; errorCode: string };

type AccountDeletionRequestRow = {
  job_id: string;
  job_status: AccountDeletionStatus;
};

type AccountDeletionClaimRow = {
  job_id: string;
  user_id: string;
  job_status: Exclude<AccountDeletionStatus, "completed">;
  claim_token: string;
  claim_expires_at: string;
};

export async function requestAccountDeletion(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<AccountDeletionRequest> {
  const { data, error } = await supabaseAdmin.rpc(
    "request_account_deletion",
    { p_user_id: userId },
  );

  if (error) {
    throw new Error(`Could not persist account deletion: ${error.message}`);
  }

  const row = ((data ?? []) as AccountDeletionRequestRow[])[0];
  if (!row?.job_id || !isAccountDeletionStatus(row.job_status)) {
    throw new Error("Account deletion intake returned an invalid receipt.");
  }

  return {
    jobId: row.job_id,
    status: row.job_status,
  };
}

export async function claimAccountDeletionJobs(
  supabaseAdmin: SupabaseClient,
  limit: number,
  targetUserId?: string,
): Promise<AccountDeletionClaim[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "claim_account_deletion_jobs",
    {
      p_limit: limit,
      p_target_user_id: targetUserId ?? null,
    },
  );

  if (error) {
    throw new Error(`Could not claim account deletions: ${error.message}`);
  }

  return ((data ?? []) as AccountDeletionClaimRow[]).map((row) => {
    if (
      !row.job_id ||
      !row.user_id ||
      !row.claim_token ||
      !row.claim_expires_at ||
      (row.job_status !== "pending" &&
        row.job_status !== "storage_pending" &&
        row.job_status !== "auth_pending")
    ) {
      throw new Error("Account deletion claim returned invalid state.");
    }

    return {
      jobId: row.job_id,
      userId: row.user_id,
      status: row.job_status,
      claimToken: row.claim_token,
      claimExpiresAt: row.claim_expires_at,
    };
  });
}

export async function completeAccountDeletionCleanup(
  supabaseAdmin: SupabaseClient,
  claim: AccountDeletionClaim,
): Promise<AccountDeletionCleanupPhase> {
  const { data, error } = await supabaseAdmin.rpc(
    "complete_account_deletion_cleanup",
    {
      p_job_id: claim.jobId,
      p_claim_token: claim.claimToken,
    },
  );

  if (error) {
    throw new Error(
      `Could not complete account deletion cleanup: ${error.message}`,
    );
  }
  if (data !== "storage_pending" && data !== "auth_pending") {
    throw new Error("Account deletion cleanup returned invalid state.");
  }
  return data;
}

export async function finishAccountDeletionAttempt(
  supabaseAdmin: SupabaseClient,
  claim: AccountDeletionClaim,
  authDeleted: boolean,
  errorCode: string | null,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc(
    "finish_account_deletion_attempt",
    {
      p_job_id: claim.jobId,
      p_claim_token: claim.claimToken,
      p_auth_deleted: authDeleted,
      p_error_code: errorCode,
    },
  );

  if (error) {
    throw new Error(
      `Could not finish account deletion attempt: ${error.message}`,
    );
  }
}

export async function deleteAuthProfile(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<AuthDeletionResult> {
  const { error } = await supabaseAdmin.auth.admin.deleteUser(userId);
  if (!error) return { succeeded: true };

  const status = typeof error.status === "number" ? error.status : null;
  if (status === 404 || error.code === "user_not_found") {
    return { succeeded: true };
  }

  return {
    succeeded: false,
    errorCode: safeAuthErrorCode(error.code, status),
  };
}

function isAccountDeletionStatus(
  value: unknown,
): value is AccountDeletionStatus {
  return value === "pending" || value === "storage_pending" ||
    value === "auth_pending" || value === "completed";
}

function safeAuthErrorCode(
  code: string | undefined,
  status: number | null,
): string {
  if (code && /^[a-z][a-z0-9_]{1,63}$/.test(code)) return code;
  return status ? `auth_http_${status}` : "auth_delete_failed";
}
