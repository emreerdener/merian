import type { SupabaseClient } from "@supabase/supabase-js";
import { deleteMergedGhostAuthUser } from "../merge-ghost-profile/db.ts";
import { preserveRevenueCatAccessForGhostMerge } from "../merge-ghost-profile/revenuecat.ts";
import {
  claimGhostMergeAuthCleanups,
  finishGhostMergeAuthCleanup,
  type GhostMergeCleanupClaim,
} from "./db.ts";

const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 100;

export type ReconcileGhostProfileMergesResult = {
  claimed: number;
  deleted: number;
  failed: number;
  errors: Array<{
    code: string;
  }>;
};

type CleanupResult =
  | { succeeded: true }
  | { succeeded: false; errorCode: string };

export type ReconcileGhostProfileMergeDependencies = {
  claim?: (
    supabaseAdmin: SupabaseClient,
    limit: number,
  ) => Promise<GhostMergeCleanupClaim[]>;
  deleteAuthUser?: (
    ghostUserId: string,
    supabaseAdmin: SupabaseClient,
  ) => Promise<CleanupResult>;
  preserveRevenueCatAccess?: (
    ghostUserId: string,
    targetUserId: string,
  ) => Promise<CleanupResult>;
  finish?: (
    supabaseAdmin: SupabaseClient,
    claim: GhostMergeCleanupClaim,
    succeeded: boolean,
    errorCode: string | null,
  ) => Promise<void>;
};

const SAFE_FAILURE_CODE = /^[a-z][a-z0-9_]{1,63}$/;

function safeFailureCode(value: unknown): string {
  const candidate = typeof value === "string"
    ? value
    : value instanceof Error
    ? value.name
    : typeof value;
  return SAFE_FAILURE_CODE.test(candidate) ? candidate : "cleanup_failed";
}

function recordFailure(
  result: ReconcileGhostProfileMergesResult,
  value: unknown,
): void {
  result.failed += 1;
  result.errors.push({ code: safeFailureCode(value) });
}

export async function reconcileGhostProfileMerges(
  supabaseAdmin: SupabaseClient,
  requestedLimit = DEFAULT_LIMIT,
  dependencies: ReconcileGhostProfileMergeDependencies = {},
): Promise<ReconcileGhostProfileMergesResult> {
  const limit = Math.min(
    Math.max(Math.trunc(requestedLimit) || DEFAULT_LIMIT, 1),
    MAX_LIMIT,
  );
  const claim = dependencies.claim ?? claimGhostMergeAuthCleanups;
  const preserveRevenueCatAccess = dependencies.preserveRevenueCatAccess ??
    ((ghostUserId, targetUserId) =>
      preserveRevenueCatAccessForGhostMerge(
        ghostUserId,
        targetUserId,
        Deno.env.get("REVENUECAT_SECRET_API_KEY")?.trim() ?? "",
      ));
  const deleteAuthUser = dependencies.deleteAuthUser ??
    deleteMergedGhostAuthUser;
  const finish = dependencies.finish ?? finishGhostMergeAuthCleanup;
  const claims = await claim(supabaseAdmin, limit);
  const result: ReconcileGhostProfileMergesResult = {
    claimed: claims.length,
    deleted: 0,
    failed: 0,
    errors: [],
  };

  for (const cleanupClaim of claims) {
    try {
      const revenueCatHandoff = await preserveRevenueCatAccess(
        cleanupClaim.ghostUserId,
        cleanupClaim.targetUserId,
      );
      if (!revenueCatHandoff.succeeded) {
        await finish(
          supabaseAdmin,
          cleanupClaim,
          false,
          revenueCatHandoff.errorCode,
        );
        recordFailure(result, revenueCatHandoff.errorCode);
        continue;
      }

      const cleanup = await deleteAuthUser(
        cleanupClaim.ghostUserId,
        supabaseAdmin,
      );
      await finish(
        supabaseAdmin,
        cleanupClaim,
        cleanup.succeeded,
        cleanup.succeeded ? null : cleanup.errorCode,
      );

      if (cleanup.succeeded) {
        result.deleted += 1;
      } else {
        recordFailure(result, cleanup.errorCode);
      }
    } catch (error) {
      recordFailure(result, error);
    }
  }

  return result;
}
