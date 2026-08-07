import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type AppleRevocationResult,
  revokeAppleRefreshToken,
} from "../_shared/appleSignIn.ts";
import {
  type AccountDeletionClaim,
  type AccountDeletionCleanupPhase,
  claimAccountDeletionJobs,
  completeAccountDeletionCleanup,
  completeAccountDeletionProviderRevocation,
  deleteAuthProfile,
  finishAccountDeletionAttempt,
  getAccountDeletionProviderToken,
  type ManualRevocationAcceptance,
  type ManualRevocationDeliveryAttempt,
  prepareAccountDeletionManualRevocationDelivery,
  type ProviderRevocationToken,
  recordAccountDeletionManualRevocationAcceptance,
} from "./db.ts";
import {
  type ManualRevocationDeliveryResult,
  sendManualAppleRevocationEmail,
} from "./manualRevocationEmail.ts";

const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 100;

export type AccountDeletionWorkerResult = {
  claimed: number;
  completed: number;
  deferred: number;
  waitingForStorage: number;
  waitingForManualDelivery: number;
  failures: Array<{
    jobId: string;
    stage:
      | "cleanup"
      | "provider"
      | "manual_delivery"
      | "auth"
      | "completion";
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
  ) => Promise<AccountDeletionCleanupPhase>;
  getProviderToken?: (
    supabaseAdmin: SupabaseClient,
    claim: AccountDeletionClaim,
  ) => Promise<ProviderRevocationToken>;
  revokeProvider?: (refreshToken: string) => Promise<AppleRevocationResult>;
  completeProvider?: (
    supabaseAdmin: SupabaseClient,
    claim: AccountDeletionClaim,
  ) => Promise<void>;
  prepareManualRevocationDelivery?: (
    supabaseAdmin: SupabaseClient,
    claim: AccountDeletionClaim,
  ) => Promise<ManualRevocationDeliveryAttempt>;
  sendManualRevocationEmail?: (
    recipientEmail: string,
    attemptId: string,
    idempotencyKey: string,
  ) => Promise<ManualRevocationDeliveryResult>;
  recordManualRevocationAcceptance?: (
    supabaseAdmin: SupabaseClient,
    claim: AccountDeletionClaim,
    attemptId: string,
    providerDeliveryId: string,
  ) => Promise<ManualRevocationAcceptance>;
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
  const getProviderToken = dependencies.getProviderToken ??
    getAccountDeletionProviderToken;
  const revokeProvider = dependencies.revokeProvider ??
    revokeAppleRefreshToken;
  const completeProvider = dependencies.completeProvider ??
    completeAccountDeletionProviderRevocation;
  const prepareManualRevocationDelivery =
    dependencies.prepareManualRevocationDelivery ??
      prepareAccountDeletionManualRevocationDelivery;
  const sendManualRevocationEmail = dependencies.sendManualRevocationEmail ??
    sendManualAppleRevocationEmail;
  const recordManualRevocationAcceptance =
    dependencies.recordManualRevocationAcceptance ??
      recordAccountDeletionManualRevocationAcceptance;
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
    waitingForStorage: 0,
    waitingForManualDelivery: 0,
    failures: [],
  };

  for (const claim of claims) {
    let stage:
      | "cleanup"
      | "provider"
      | "manual_delivery"
      | "auth"
      | "completion" = "cleanup";

    try {
      // Re-run the idempotent cleanup even for auth_pending retries. This
      // revalidates the database immediately before the external Auth delete
      // and removes any state written by an older rollout worker. Relational
      // completion means retained scans are ownerless tombstones; it never
      // depends on a synthetic public or Auth user.
      const cleanupPhase = await cleanup(supabaseAdmin, claim);
      if (cleanupPhase === "storage_pending") {
        result.waitingForStorage += 1;
        continue;
      }

      if (cleanupPhase === "manual_revocation_delivery_waiting") {
        result.waitingForManualDelivery += 1;
        continue;
      }

      if (cleanupPhase === "provider_revocation_pending") {
        stage = "provider";
        const credential = await getProviderToken(supabaseAdmin, claim);
        const providerResult = await revokeProvider(credential.refreshToken);
        if (!providerResult.succeeded) {
          const errorCode = providerResult.errorCode ??
            "apple_revoke_failed";
          await finish(supabaseAdmin, claim, false, errorCode);
          recordDeferred(result, claim, "provider", errorCode);
          continue;
        }

        // Apple documents HTTP 200 as idempotent for both newly revoked and
        // previously invalid tokens. Persist that outcome and destroy the
        // Vault secret before the Auth call becomes reachable.
        await completeProvider(supabaseAdmin, claim);
      }

      if (cleanupPhase === "manual_revocation_delivery_pending") {
        stage = "manual_delivery";
        const attempt = await prepareManualRevocationDelivery(
          supabaseAdmin,
          claim,
        );
        const delivery = await sendManualRevocationEmail(
          attempt.email,
          attempt.attemptId,
          attempt.idempotencyKey,
        );
        if (!delivery.succeeded) {
          await finish(supabaseAdmin, claim, false, delivery.errorCode);
          recordDeferred(
            result,
            claim,
            "manual_delivery",
            delivery.errorCode,
          );
          continue;
        }

        // Provider acceptance is dispatch evidence only. The database binds it
        // to the pre-created attempt and keeps Auth fenced unless a matching,
        // signature-verified delivery event was already journaled.
        const acceptance = await recordManualRevocationAcceptance(
          supabaseAdmin,
          claim,
          attempt.attemptId,
          delivery.providerDeliveryId,
        );
        if (acceptance === "delivery_pending") {
          result.waitingForManualDelivery += 1;
          continue;
        }
        if (acceptance === "retry_required") {
          recordDeferred(
            result,
            claim,
            "manual_delivery",
            "manual_revocation_delivery_retry_required",
          );
          continue;
        }
      }

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
        : stage === "provider"
        ? "provider_revocation_failed"
        : stage === "manual_delivery"
        ? "manual_revocation_delivery_failed"
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
  stage:
    | "cleanup"
    | "provider"
    | "manual_delivery"
    | "auth"
    | "completion",
  code: string,
): void {
  result.deferred += 1;
  result.failures.push({
    jobId: claim.jobId,
    stage,
    code,
  });
}
