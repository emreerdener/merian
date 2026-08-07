import type { SupabaseClient } from "@supabase/supabase-js";

export type AccountDeletionStatus =
  | "pending"
  | "storage_pending"
  | "auth_pending"
  | "completed";

export type AccountDeletionCleanupPhase =
  | "storage_pending"
  | "provider_revocation_pending"
  | "manual_revocation_delivery_pending"
  | "manual_revocation_delivery_waiting"
  | "auth_pending";

export type AccountDeletionRequest = {
  jobId: string;
  status: AccountDeletionStatus;
  manualProviderRevocationRequired: boolean;
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

export type ProviderRevocationToken = {
  refreshToken: string;
};

export type ManualRevocationDeliveryAttempt = {
  email: string;
  attemptId: string;
  idempotencyKey: string;
};

export type ManualRevocationAcceptance =
  | "delivered"
  | "delivery_pending"
  | "retry_required";

type AccountDeletionRequestRow = {
  job_id: string;
  job_status: AccountDeletionStatus;
  manual_provider_revocation_required: boolean;
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
  if (
    !row?.job_id ||
    !isAccountDeletionStatus(row.job_status) ||
    typeof row.manual_provider_revocation_required !== "boolean"
  ) {
    throw new Error("Account deletion intake returned an invalid receipt.");
  }

  return {
    jobId: row.job_id,
    status: row.job_status,
    manualProviderRevocationRequired: row.manual_provider_revocation_required,
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
  if (
    data !== "storage_pending" &&
    data !== "provider_revocation_pending" &&
    data !== "manual_revocation_delivery_pending" &&
    data !== "manual_revocation_delivery_waiting" &&
    data !== "auth_pending"
  ) {
    throw new Error("Account deletion cleanup returned invalid state.");
  }
  return data;
}

export async function getAccountDeletionProviderToken(
  supabaseAdmin: SupabaseClient,
  claim: AccountDeletionClaim,
): Promise<ProviderRevocationToken> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_account_deletion_provider_token",
    {
      p_job_id: claim.jobId,
      p_claim_token: claim.claimToken,
    },
  );

  if (error) {
    throw new Error("Could not load the provider revocation credential.");
  }

  const row = ((data ?? []) as Array<{ refresh_token?: unknown }>)[0];
  if (
    typeof row?.refresh_token !== "string" ||
    row.refresh_token.length < 16 ||
    row.refresh_token.length > 8_192 ||
    containsAsciiControlCharacter(row.refresh_token)
  ) {
    throw new Error("Provider revocation credential was invalid.");
  }

  return { refreshToken: row.refresh_token };
}

function containsAsciiControlCharacter(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code <= 0x1F || code === 0x7F) {
      return true;
    }
  }
  return false;
}

export async function completeAccountDeletionProviderRevocation(
  supabaseAdmin: SupabaseClient,
  claim: AccountDeletionClaim,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc(
    "complete_account_deletion_provider_revocation",
    {
      p_job_id: claim.jobId,
      p_claim_token: claim.claimToken,
    },
  );

  if (error) {
    throw new Error("Could not complete provider revocation.");
  }
}

export async function prepareAccountDeletionManualRevocationDelivery(
  supabaseAdmin: SupabaseClient,
  claim: AccountDeletionClaim,
): Promise<ManualRevocationDeliveryAttempt> {
  const { data, error } = await supabaseAdmin.rpc(
    "prepare_account_deletion_manual_revocation_delivery",
    {
      p_job_id: claim.jobId,
      p_claim_token: claim.claimToken,
    },
  );

  if (error) {
    throw new Error("Could not prepare manual revocation delivery.");
  }

  const row = ((data ?? []) as Array<{
    recipient_email?: unknown;
    attempt_token?: unknown;
    idempotency_key?: unknown;
  }>)[0];
  if (
    typeof row?.recipient_email !== "string" ||
    row.recipient_email.length < 3 ||
    row.recipient_email.length > 320 ||
    containsAsciiControlCharacter(row.recipient_email) ||
    !/^[^\s@]+@[^\s@]+$/.test(row.recipient_email) ||
    typeof row.attempt_token !== "string" ||
    !isUuid(row.attempt_token) ||
    typeof row.idempotency_key !== "string" ||
    row.idempotency_key !==
      `account-deletion-manual-apple/${row.attempt_token}`
  ) {
    throw new Error("Manual revocation delivery attempt was invalid.");
  }

  return {
    email: row.recipient_email,
    attemptId: row.attempt_token,
    idempotencyKey: row.idempotency_key,
  };
}

export async function recordAccountDeletionManualRevocationAcceptance(
  supabaseAdmin: SupabaseClient,
  claim: AccountDeletionClaim,
  attemptId: string,
  providerDeliveryId: string,
): Promise<ManualRevocationAcceptance> {
  const { data, error } = await supabaseAdmin.rpc(
    "record_account_deletion_manual_revocation_acceptance",
    {
      p_job_id: claim.jobId,
      p_claim_token: claim.claimToken,
      p_attempt_token: attemptId,
      p_provider_delivery_id: providerDeliveryId,
    },
  );

  if (error) {
    throw new Error("Could not record manual revocation acceptance.");
  }
  if (
    data !== "delivered" &&
    data !== "delivery_pending" &&
    data !== "retry_required"
  ) {
    throw new Error("Manual revocation acceptance returned invalid state.");
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

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function safeAuthErrorCode(
  code: string | undefined,
  status: number | null,
): string {
  if (code && /^[a-z][a-z0-9_]{1,63}$/.test(code)) return code;
  return status ? `auth_http_${status}` : "auth_delete_failed";
}
