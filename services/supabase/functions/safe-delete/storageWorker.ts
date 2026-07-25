import type { SupabaseClient } from "@supabase/supabase-js";
import {
  deleteR2Object,
  getR2Config,
  listR2ObjectKeys,
  type R2Config,
  type R2ObjectPage,
} from "../_shared/aws.ts";
import { mapWithConcurrencyLimit } from "../_shared/concurrency.ts";
import {
  advanceStorageDeletionJob,
  claimStorageDeletionJobs,
  failStorageDeletionJob,
  type StorageDeletionClaim,
} from "./storageDb.ts";

// One page can require seven waves of 10-second R2 DELETE deadlines. Keep the
// invocation ceiling low enough that even provider timeouts fit comfortably
// inside the Edge wall-clock budget; pg_cron will resume remaining leases.
const DEFAULT_LIMIT = 4;
const MAX_LIMIT = 4;
const PAGE_SIZE = 50;
const DELETE_CONCURRENCY = 8;

export type StorageDeletionWorkerResult = {
  claimed: number;
  completed: number;
  advanced: number;
  deferred: number;
  failures: Array<{ deletionId: string; code: string }>;
};

export type StorageDeletionWorkerDependencies = {
  claim?: (
    supabaseAdmin: SupabaseClient,
    limit: number,
  ) => Promise<StorageDeletionClaim[]>;
  list?: (
    claim: StorageDeletionClaim,
    config: R2Config,
  ) => Promise<R2ObjectPage>;
  delete?: (key: string, config: R2Config) => Promise<Response>;
  advance?: (
    supabaseAdmin: SupabaseClient,
    claim: StorageDeletionClaim,
    lastKey: string | null,
    prefixFinished: boolean,
  ) => Promise<"pending" | "verifying" | "completed">;
  fail?: (
    supabaseAdmin: SupabaseClient,
    claim: StorageDeletionClaim,
    errorCode: string,
  ) => Promise<void>;
  config?: () => R2Config;
};

export async function processPendingStorageDeletions(
  supabaseAdmin: SupabaseClient,
  limit = DEFAULT_LIMIT,
  dependencies: StorageDeletionWorkerDependencies = {},
): Promise<StorageDeletionWorkerResult> {
  const boundedLimit = Math.min(
    Math.max(Math.trunc(limit), 1),
    MAX_LIMIT,
  );
  const claimJobs = dependencies.claim ?? claimStorageDeletionJobs;
  const list = dependencies.list ??
    ((claim, config) =>
      listR2ObjectKeys(
        claim.objectPrefix,
        claim.startAfterKey,
        config,
        PAGE_SIZE,
      ));
  const deleteObject = dependencies.delete ?? deleteR2Object;
  const advance = dependencies.advance ?? advanceStorageDeletionJob;
  const fail = dependencies.fail ?? failStorageDeletionJob;
  const config = (dependencies.config ?? getR2Config)();
  const claims = await claimJobs(supabaseAdmin, boundedLimit);
  const result: StorageDeletionWorkerResult = {
    claimed: claims.length,
    completed: 0,
    advanced: 0,
    deferred: 0,
    failures: [],
  };

  for (const claim of claims) {
    try {
      const page = await list(claim, config);
      await mapWithConcurrencyLimit(
        page.keys,
        DELETE_CONCURRENCY,
        async (key) => {
          const response = await deleteObject(key, config);
          if (!response.ok && response.status !== 404) {
            await response.body?.cancel();
            throw new Error(`R2 delete returned HTTP ${response.status}.`);
          }
          await response.body?.cancel();
        },
      );

      const status = await advance(
        supabaseAdmin,
        claim,
        page.keys.at(-1) ?? null,
        !page.isTruncated,
      );
      result.advanced += 1;
      if (status === "completed") result.completed += 1;
    } catch {
      result.deferred += 1;
      result.failures.push({
        deletionId: claim.deletionId,
        code: "r2_erasure_failed",
      });
      try {
        await fail(
          supabaseAdmin,
          claim,
          "r2_erasure_failed",
        );
      } catch {
        // The durable lease can be reclaimed after expiration.
      }
    }
  }

  return result;
}
