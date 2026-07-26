import { SupabaseClient } from "@supabase/supabase-js";

import {
  getR2ReadConfig,
  headR2Object,
  type R2Config,
  r2ObjectKeyFromPublicUrl,
} from "../_shared/aws.ts";
import { mapWithConcurrencyLimit } from "../_shared/concurrency.ts";
import {
  claimExploreMediaHealthChecks,
  type ExploreMediaHealthClaim,
  type ExploreMediaHealthOutcome,
  type ExploreMediaHealthRunInsert,
  recordExploreMediaHealthCheck,
  recordExploreMediaHealthRun,
} from "./db.ts";

const DEFAULT_LIMIT = 200;
const DEFAULT_LEASE_SECONDS = 300;
const R2_HEAD_CONCURRENCY = 24;
const MAX_ERROR_SAMPLES = 50;

export interface ReconcileExploreMediaHealthOptions {
  limit?: number;
  leaseSeconds?: number;
  now?: Date;
}

export interface ReconcileExploreMediaHealthResult {
  claimed: number;
  healthy: number;
  missingObservations: number;
  retryableErrors: number;
  errorCount: number;
  omittedErrors: number;
  errors: Array<{
    mediaId: string;
    postId: string;
    reason: string;
  }>;
}

interface ReconcileDependencies {
  claimChecks?: typeof claimExploreMediaHealthChecks;
  recordCheck?: typeof recordExploreMediaHealthCheck;
  recordRun?: typeof recordExploreMediaHealthRun;
  headObject?: typeof headR2Object;
  r2Config?: R2Config;
}

interface ObjectCheck {
  status: number | null;
  outcome: ExploreMediaHealthOutcome;
}

function safeOriginFailureReason(error: unknown): string {
  if (error instanceof DOMException && error.name === "TimeoutError") {
    return "origin_check_timeout";
  }
  if (
    error instanceof Error &&
    error.message ===
      "Explore media URL is not canonical durable media for its owner."
  ) {
    return "origin_key_rejected";
  }
  return "origin_check_failed";
}

function appendErrorSample(
  result: ReconcileExploreMediaHealthResult,
  mediaId: string,
  postId: string,
  reason: string,
): void {
  result.errorCount += 1;
  if (result.errors.length < MAX_ERROR_SAMPLES) {
    result.errors.push({ mediaId, postId, reason });
  } else {
    result.omittedErrors += 1;
  }
}

function boundedInteger(
  value: number | undefined,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  if (value === undefined || !Number.isFinite(value)) return fallback;
  return Math.min(Math.max(Math.trunc(value), minimum), maximum);
}

async function checkPublicR2Object(
  publicUrl: string,
  ownerId: string,
  r2Config: R2Config,
  headObject: typeof headR2Object,
): Promise<ObjectCheck> {
  const key = r2ObjectKeyFromPublicUrl(publicUrl);
  const keyParts = key?.split("/") ?? [];
  if (
    !key ||
    keyParts.length !== 4 ||
    keyParts[0] !== "public_uploads" ||
    (keyParts[1] !== "free" && keyParts[1] !== "pro") ||
    keyParts[2].toLowerCase() !== ownerId.toLowerCase() ||
    !keyParts[3] ||
    keyParts[3].includes("..") ||
    keyParts[3].includes("%")
  ) {
    throw new Error(
      "Explore media URL is not canonical durable media for its owner.",
    );
  }

  const response = await headObject(key, r2Config);
  await response.body?.cancel();
  if (response.ok) return { status: response.status, outcome: "healthy" };
  if (response.status === 404) {
    return { status: response.status, outcome: "missing" };
  }
  return { status: response.status, outcome: "retryable_error" };
}

export async function inspectExploreMediaClaim(
  claim: ExploreMediaHealthClaim,
  r2Config: R2Config,
  headObject: typeof headR2Object = headR2Object,
): Promise<{
  outcome: ExploreMediaHealthOutcome;
  urlHttpStatus: number | null;
  thumbnailHttpStatus: number | null;
}> {
  const thumbnailUrl = claim.thumbnail_url?.trim();
  const distinctThumbnail = thumbnailUrl && thumbnailUrl !== claim.url
    ? checkPublicR2Object(
      thumbnailUrl,
      claim.user_id,
      r2Config,
      headObject,
    )
    : null;
  const [urlResult, thumbnailResult] = await Promise.allSettled([
    checkPublicR2Object(
      claim.url,
      claim.user_id,
      r2Config,
      headObject,
    ),
    distinctThumbnail ?? Promise.resolve(null),
  ]);

  if (urlResult.status === "rejected") throw urlResult.reason;
  const urlCheck = urlResult.value;
  const thumbnailCheck = thumbnailResult.status === "fulfilled" &&
      thumbnailResult.value
    ? thumbnailResult.value
    : distinctThumbnail
    ? { status: null, outcome: "retryable_error" } satisfies ObjectCheck
    : urlCheck;

  return {
    // The primary object decides whether this media item is usable. A missing
    // poster is recorded and omitted from projections, but must not hide an
    // otherwise playable video or audio observation.
    outcome: urlCheck.outcome,
    urlHttpStatus: urlCheck.status,
    thumbnailHttpStatus: thumbnailCheck.status,
  };
}

export async function reconcileExploreMediaHealth(
  supabaseAdmin: SupabaseClient,
  options: ReconcileExploreMediaHealthOptions = {},
  dependencies: ReconcileDependencies = {},
): Promise<ReconcileExploreMediaHealthResult> {
  const startedAt = options.now ?? new Date();
  const limit = boundedInteger(options.limit, DEFAULT_LIMIT, 1, 500);
  const leaseSeconds = boundedInteger(
    options.leaseSeconds,
    DEFAULT_LEASE_SECONDS,
    30,
    600,
  );
  const claimChecks = dependencies.claimChecks ??
    claimExploreMediaHealthChecks;
  const recordCheck = dependencies.recordCheck ??
    recordExploreMediaHealthCheck;
  const recordRun = dependencies.recordRun ?? recordExploreMediaHealthRun;
  const headObject = dependencies.headObject ?? headR2Object;
  let r2Config: R2Config;
  let claims: ExploreMediaHealthClaim[];
  try {
    r2Config = dependencies.r2Config ?? getR2ReadConfig();
    claims = await claimChecks(limit, leaseSeconds, supabaseAdmin);
  } catch (error) {
    const reason = error instanceof Error &&
        error.message === "Required R2 read configuration is missing."
      ? "r2_read_config_missing"
      : "claim_failed";
    try {
      await recordRun({
        started_at: startedAt.toISOString(),
        finished_at: new Date().toISOString(),
        status: "failed",
        claimed_count: 0,
        healthy_count: 0,
        missing_observation_count: 0,
        retryable_error_count: 0,
        error_count: 1,
        errors: [{ reason }],
      }, supabaseAdmin);
    } catch {
      // The endpoint emits one sanitized failure event if audit persistence is
      // unavailable too.
    }
    throw error;
  }

  const result: ReconcileExploreMediaHealthResult = {
    claimed: claims.length,
    healthy: 0,
    missingObservations: 0,
    retryableErrors: 0,
    errorCount: 0,
    omittedErrors: 0,
    errors: [],
  };

  await mapWithConcurrencyLimit(
    claims,
    R2_HEAD_CONCURRENCY,
    async (claim) => {
      let outcome: ExploreMediaHealthOutcome = "retryable_error";
      let urlHttpStatus: number | null = null;
      let thumbnailHttpStatus: number | null = null;
      try {
        const check = await inspectExploreMediaClaim(
          claim,
          r2Config,
          headObject,
        );
        outcome = check.outcome;
        urlHttpStatus = check.urlHttpStatus;
        thumbnailHttpStatus = check.thumbnailHttpStatus;
      } catch (error) {
        appendErrorSample(
          result,
          claim.media_id,
          claim.post_id,
          safeOriginFailureReason(error),
        );
      }

      try {
        await recordCheck(
          claim,
          outcome,
          urlHttpStatus,
          thumbnailHttpStatus,
          supabaseAdmin,
        );
        if (outcome === "healthy") result.healthy += 1;
        else if (outcome === "missing") result.missingObservations += 1;
        else result.retryableErrors += 1;
      } catch {
        appendErrorSample(
          result,
          claim.media_id,
          claim.post_id,
          "result_record_failed",
        );
      }
    },
  );

  const finishedAt = options.now ?? new Date();
  const run: ExploreMediaHealthRunInsert = {
    started_at: startedAt.toISOString(),
    finished_at: finishedAt.toISOString(),
    status: result.errorCount === 0 ? "success" : "partial_failure",
    claimed_count: result.claimed,
    healthy_count: result.healthy,
    missing_observation_count: result.missingObservations,
    retryable_error_count: result.retryableErrors,
    error_count: result.errorCount,
    errors: result.errors,
  };

  try {
    await recordRun(run, supabaseAdmin);
  } catch {
    appendErrorSample(result, "", "", "audit_write_failed");
  }
  return result;
}
