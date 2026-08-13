import type { SupabaseClient } from "@supabase/supabase-js";

export type AccountDeletionStatus =
  | "pending"
  | "storage_pending"
  | "auth_pending"
  | "completed";

export type AccountDeletionCleanupPhase =
  | "storage_pending"
  | "provider_revocation_pending"
  | "auth_pending";

export type AccountDeletionRequest = {
  jobId: string;
  status: AccountDeletionStatus;
  manualProviderRevocationRequired: boolean;
  recoveryExpiresAt: string | null;
};

export type AccountDeletionRecoveryReceipt = {
  status:
    | "not_committed"
    | "preparation_expired"
    | "pending"
    | "completed";
  manualProviderRevocationRequired: boolean;
  recoveryExpiresAt: string;
  recoveryAcknowledged: boolean;
};

export type AccountDeletionRecoveryPreparation = {
  prepared: true;
  recoveryExpiresAt: string;
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

type AccountDeletionRequestRow = {
  job_id: string;
  job_status: AccountDeletionStatus;
  manual_provider_revocation_required: boolean;
  recovery_expires_at?: unknown;
};

type AccountDeletionRecoveryRow = {
  deletion_status?: unknown;
  manual_provider_revocation_required?: unknown;
  recovery_expires_at?: unknown;
  recovery_acknowledged?: unknown;
};

type AccountDeletionRecoveryPreparationRow = {
  recovery_prepared?: unknown;
  recovery_expires_at?: unknown;
};

type AccountDeletionClaimRow = {
  job_id: string;
  user_id: string;
  job_status: Exclude<AccountDeletionStatus, "completed">;
  claim_token: string;
  claim_expires_at: string;
};

export class AccountDeletionIntakeError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "AccountDeletionIntakeError";
  }
}

export class AccountDeletionRecoveryError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "AccountDeletionRecoveryError";
  }
}

export async function requestAccountDeletion(
  userId: string,
  supabaseAdmin: SupabaseClient,
  recoverySecretHash: string | null = null,
): Promise<AccountDeletionRequest> {
  const { data, error } = await supabaseAdmin.rpc(
    recoverySecretHash === null
      ? "request_account_deletion"
      : "request_account_deletion_with_recovery",
    recoverySecretHash === null
      ? { p_user_id: userId }
      : { p_user_id: userId, p_secret_hash: recoverySecretHash },
  );

  if (error) {
    if (
      error.message.toLowerCase().includes(
        "signout_handoff_destination_deletion_blocked",
      )
    ) {
      throw new AccountDeletionIntakeError(
        "purchase_continuity_pending",
        409,
        "Finish signing out before deleting this account.",
      );
    }
    throw new Error(`Could not persist account deletion: ${error.message}`);
  }

  const row = ((data ?? []) as AccountDeletionRequestRow[])[0];
  if (
    !row?.job_id ||
    !isAccountDeletionStatus(row.job_status) ||
    typeof row.manual_provider_revocation_required !== "boolean" ||
    (recoverySecretHash !== null &&
      !isTimestamp(row.recovery_expires_at))
  ) {
    throw new Error("Account deletion intake returned an invalid receipt.");
  }

  return {
    jobId: row.job_id,
    status: row.job_status,
    manualProviderRevocationRequired: row.manual_provider_revocation_required,
    recoveryExpiresAt: recoverySecretHash === null
      ? null
      : row.recovery_expires_at as string,
  };
}

export async function prepareAccountDeletionRecoveryV2(
  userId: string,
  supabaseAdmin: SupabaseClient,
  recoverySecretHash: string,
  acknowledgementSecretHash: string,
): Promise<AccountDeletionRecoveryPreparation> {
  const { data, error } = await supabaseAdmin.rpc(
    "prepare_account_deletion_recovery_v2",
    {
      p_user_id: userId,
      p_recovery_secret_hash: recoverySecretHash,
      p_acknowledgement_secret_hash: acknowledgementSecretHash,
    },
  );
  if (error) {
    throw mapAccountDeletionIntakeError(error.message);
  }
  const row = ((data ?? []) as AccountDeletionRecoveryPreparationRow[])[0];
  if (
    row?.recovery_prepared !== true || !isTimestamp(row.recovery_expires_at)
  ) {
    throw new Error(
      "Account deletion preparation returned an invalid receipt.",
    );
  }
  return {
    prepared: true,
    recoveryExpiresAt: row.recovery_expires_at,
  };
}

export async function requestAccountDeletionV2(
  userId: string,
  supabaseAdmin: SupabaseClient,
  recoverySecretHash: string,
): Promise<AccountDeletionRequest> {
  const { data, error } = await supabaseAdmin.rpc(
    "request_account_deletion_with_recovery_v2",
    {
      p_user_id: userId,
      p_recovery_secret_hash: recoverySecretHash,
    },
  );
  if (error) {
    throw mapAccountDeletionIntakeError(error.message);
  }
  return parseAccountDeletionRequestRow(data, true);
}

export async function recoverAccountDeletion(
  supabaseAdmin: SupabaseClient,
  recoverySecretHash: string,
  acknowledge: boolean,
): Promise<AccountDeletionRecoveryReceipt> {
  const { data, error } = await supabaseAdmin.rpc(
    "recover_account_deletion",
    {
      p_secret_hash: recoverySecretHash,
      p_acknowledge: acknowledge,
    },
  );
  if (error) {
    const normalized = error.message.toLowerCase();
    if (normalized.includes("account_deletion_recovery_expired")) {
      throw new AccountDeletionRecoveryError(
        "account_deletion_recovery_expired",
        410,
        "Account deletion recovery has expired.",
      );
    }
    if (normalized.includes("account_deletion_recovery_invalid")) {
      throw new AccountDeletionRecoveryError(
        "account_deletion_recovery_invalid",
        404,
        "Account deletion recovery is unavailable.",
      );
    }
    throw new AccountDeletionRecoveryError(
      "account_deletion_recovery_unavailable",
      503,
      "Account deletion recovery is temporarily unavailable.",
    );
  }

  const row = ((data ?? []) as AccountDeletionRecoveryRow[])[0];
  if (
    (row?.deletion_status !== "pending" &&
      row?.deletion_status !== "completed") ||
    typeof row.manual_provider_revocation_required !== "boolean" ||
    !isTimestamp(row.recovery_expires_at) ||
    typeof row.recovery_acknowledged !== "boolean" ||
    (acknowledge && row.recovery_acknowledged !== true)
  ) {
    throw new AccountDeletionRecoveryError(
      "account_deletion_recovery_invalid_response",
      503,
      "Account deletion recovery returned an invalid receipt.",
    );
  }

  return {
    status: row.deletion_status,
    manualProviderRevocationRequired: row.manual_provider_revocation_required,
    recoveryExpiresAt: row.recovery_expires_at,
    recoveryAcknowledged: row.recovery_acknowledged,
  };
}

export async function recoverAccountDeletionV2(
  supabaseAdmin: SupabaseClient,
  capabilitySecretHash: string,
  operation: "recover" | "acknowledge",
): Promise<AccountDeletionRecoveryReceipt> {
  const { data, error } = await supabaseAdmin.rpc(
    operation === "recover"
      ? "recover_account_deletion_v2"
      : "acknowledge_account_deletion_recovery_v2",
    operation === "recover"
      ? { p_recovery_secret_hash: capabilitySecretHash }
      : { p_acknowledgement_secret_hash: capabilitySecretHash },
  );
  if (error) {
    throw mapAccountDeletionRecoveryError(error.message);
  }
  const receipt = parseAccountDeletionRecoveryRow(
    data,
    operation === "acknowledge",
    true,
  );
  if (receipt.status === "preparation_expired") {
    throw new AccountDeletionRecoveryError(
      "account_deletion_recovery_preparation_expired",
      410,
      "Account deletion preparation expired before it could authorize recovery.",
    );
  }
  return receipt;
}

export async function pruneAccountDeletionRecoveryPreparations(
  supabaseAdmin: SupabaseClient,
  limit: number,
): Promise<number> {
  const { data, error } = await supabaseAdmin.rpc(
    "prune_account_deletion_recovery_preparations",
    { p_limit: Math.max(1, Math.min(500, Math.trunc(limit))) },
  );
  if (
    error || typeof data !== "number" || !Number.isSafeInteger(data) || data < 0
  ) {
    throw new Error("Could not prune account deletion preparations.");
  }
  return data;
}

function parseAccountDeletionRequestRow(
  data: unknown,
  requiresRecoveryExpiry: boolean,
): AccountDeletionRequest {
  const row = ((data ?? []) as AccountDeletionRequestRow[])[0];
  if (
    !row?.job_id ||
    !isAccountDeletionStatus(row.job_status) ||
    typeof row.manual_provider_revocation_required !== "boolean" ||
    (requiresRecoveryExpiry && !isTimestamp(row.recovery_expires_at))
  ) {
    throw new Error("Account deletion intake returned an invalid receipt.");
  }
  return {
    jobId: row.job_id,
    status: row.job_status,
    manualProviderRevocationRequired: row.manual_provider_revocation_required,
    recoveryExpiresAt: requiresRecoveryExpiry
      ? row.recovery_expires_at as string
      : null,
  };
}

function parseAccountDeletionRecoveryRow(
  data: unknown,
  acknowledge: boolean,
  allowsNotCommitted: boolean,
): AccountDeletionRecoveryReceipt {
  const row = ((data ?? []) as AccountDeletionRecoveryRow[])[0];
  if (
    (row?.deletion_status !== "pending" &&
      row?.deletion_status !== "completed" &&
      row?.deletion_status !== "preparation_expired" &&
      !(allowsNotCommitted && row?.deletion_status === "not_committed")) ||
    typeof row.manual_provider_revocation_required !== "boolean" ||
    !isTimestamp(row.recovery_expires_at) ||
    typeof row.recovery_acknowledged !== "boolean" ||
    (acknowledge && row.recovery_acknowledged !== true)
  ) {
    throw new AccountDeletionRecoveryError(
      "account_deletion_recovery_invalid_response",
      503,
      "Account deletion recovery returned an invalid receipt.",
    );
  }
  return {
    status: row.deletion_status,
    manualProviderRevocationRequired: row.manual_provider_revocation_required,
    recoveryExpiresAt: row.recovery_expires_at,
    recoveryAcknowledged: row.recovery_acknowledged,
  };
}

function mapAccountDeletionIntakeError(message: string): Error {
  const normalized = message.toLowerCase();
  if (normalized.includes("signout_handoff_destination_deletion_blocked")) {
    return new AccountDeletionIntakeError(
      "purchase_continuity_pending",
      409,
      "Finish signing out before deleting this account.",
    );
  }
  if (
    normalized.includes("account_deletion_recovery_preparation_expired")
  ) {
    return new AccountDeletionIntakeError(
      "account_deletion_recovery_preparation_expired",
      410,
      "Account deletion preparation expired before deletion was accepted.",
    );
  }
  if (normalized.includes("account_deletion_recovery_expired")) {
    return new AccountDeletionIntakeError(
      "account_deletion_recovery_expired",
      410,
      "Account deletion preparation has expired.",
    );
  }
  return new Error(`Could not persist account deletion: ${message}`);
}

function mapAccountDeletionRecoveryError(
  message: string,
): AccountDeletionRecoveryError {
  const normalized = message.toLowerCase();
  if (
    normalized.includes("account_deletion_recovery_preparation_expired")
  ) {
    return new AccountDeletionRecoveryError(
      "account_deletion_recovery_preparation_expired",
      410,
      "Account deletion preparation expired before it could authorize recovery.",
    );
  }
  if (normalized.includes("account_deletion_recovery_expired")) {
    return new AccountDeletionRecoveryError(
      "account_deletion_recovery_expired",
      410,
      "Account deletion recovery has expired.",
    );
  }
  if (normalized.includes("account_deletion_recovery_invalid")) {
    return new AccountDeletionRecoveryError(
      "account_deletion_recovery_invalid",
      404,
      "Account deletion recovery is unavailable.",
    );
  }
  return new AccountDeletionRecoveryError(
    "account_deletion_recovery_unavailable",
    503,
    "Account deletion recovery is temporarily unavailable.",
  );
}

function isTimestamp(value: unknown): value is string {
  return typeof value === "string" &&
    value.length >= 20 &&
    value.length <= 40 &&
    Number.isFinite(Date.parse(value));
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
