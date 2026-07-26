import { SupabaseClient } from "@supabase/supabase-js";
import {
  deriveRevenueCatEntitlementState,
  fetchRevenueCatCustomerInfo,
} from "../revenuecat-webhook/subscriber.ts";
import {
  applyRevenueCatReconciliation,
  claimRevenueCatReconciliations,
  failRevenueCatReconciliation,
  getRevenueCatReconciliationHealth,
  RevenueCatReconciliationClaim,
  RevenueCatReconciliationHealth,
} from "./db.ts";

const FETCH_CONCURRENCY = 3;
// Two provider rounds fit inside the 30-second final-wave reserve even when
// every RevenueCat request reaches its ten-second fetch deadline.
const CLAIM_BATCH_SIZE = 6;
const RUNTIME_BUDGET_MS = 90_000;
const FINAL_WAVE_AND_HEALTH_RESERVE_MS = 30_000;
const MAX_SNAPSHOT_FUTURE_SKEW_MS = 5 * 60 * 1_000;
const BACKLOG_WARNING_AGE_SECONDS = 30 * 60;
const BACKLOG_CRITICAL_AGE_SECONDS = 60 * 60;

export type RevenueCatReconciliationHealthStatus =
  | "ok"
  | "warning"
  | "critical";

export interface RevenueCatReconciliationResult {
  claimed: number;
  reconciled: number;
  applied: number;
  stale: number;
  failed: number;
  claimBatches: number;
  queueDrained: boolean;
  runtimeDeadlineReached: boolean;
  healthStatus: RevenueCatReconciliationHealthStatus;
  health: RevenueCatReconciliationHealth;
}

interface RevenueCatReconciliationDependencies {
  claim?: typeof claimRevenueCatReconciliations;
  fetchCustomerInfo?: typeof fetchRevenueCatCustomerInfo;
  apply?: typeof applyRevenueCatReconciliation;
  fail?: typeof failRevenueCatReconciliation;
  health?: typeof getRevenueCatReconciliationHealth;
  fetchImpl?: typeof fetch;
  now?: () => number;
  monotonicNow?: () => number;
}

function publicFailureCode(error: unknown): string {
  if (!(error instanceof Error)) return "reconciliation_failed";
  const normalized = error.name.replaceAll(/[^A-Za-z0-9_-]/g, "_");
  return normalized.length > 0
    ? normalized.slice(0, 120)
    : "reconciliation_failed";
}

async function reconcileOne(
  claim: RevenueCatReconciliationClaim,
  apiKey: string,
  supabaseAdmin: SupabaseClient,
  dependencies: Required<
    Pick<
      RevenueCatReconciliationDependencies,
      "fetchCustomerInfo" | "apply" | "fail" | "fetchImpl" | "now"
    >
  >,
): Promise<"applied" | "stale" | "failed"> {
  try {
    const customerInfo = await dependencies.fetchCustomerInfo(
      claim.lookupAppUserId,
      apiKey,
      dependencies.fetchImpl,
    );
    if (
      customerInfo.requestDateMs >
        dependencies.now() + MAX_SNAPSHOT_FUTURE_SKEW_MS
    ) {
      throw new Error("RevenueCat snapshot timestamp is in the future.");
    }
    const entitlement = deriveRevenueCatEntitlementState(
      customerInfo,
      undefined,
      claim.allowNonSubscriptionPassGrant,
    );
    const applied = await dependencies.apply(
      claim,
      customerInfo.requestDateMs,
      entitlement.targetTier,
      entitlement.expiresAt,
      supabaseAdmin,
    );
    return applied ? "applied" : "stale";
  } catch (error) {
    console.error(
      `[reconcile-revenuecat-subscribers] user_id=${claim.userId} failed:`,
      error,
    );
    try {
      await dependencies.fail(
        claim,
        publicFailureCode(error),
        supabaseAdmin,
      );
    } catch (failureWriteError) {
      console.error(
        `[reconcile-revenuecat-subscribers] user_id=${claim.userId} failure persistence failed:`,
        failureWriteError,
      );
    }
    return "failed";
  }
}

export function revenueCatReconciliationHealthStatus(
  health: RevenueCatReconciliationHealth,
): RevenueCatReconciliationHealthStatus {
  const oldestDueAgeSeconds = health.oldestDueAgeSeconds ?? 0;
  if (oldestDueAgeSeconds >= BACKLOG_CRITICAL_AGE_SECONDS) {
    return "critical";
  }
  if (
    health.expiredClaimCount > 0 ||
    oldestDueAgeSeconds >= BACKLOG_WARNING_AGE_SECONDS
  ) {
    return "warning";
  }
  return "ok";
}

function logReconciliationHealth(
  result: RevenueCatReconciliationResult,
): void {
  const event = JSON.stringify({
    event: "revenuecat_reconciliation_health",
    status: result.healthStatus,
    claimed: result.claimed,
    claim_batches: result.claimBatches,
    reconciled: result.reconciled,
    failed: result.failed,
    queue_drained: result.queueDrained,
    runtime_deadline_reached: result.runtimeDeadlineReached,
    due_count: result.health.dueCount,
    expired_claim_count: result.health.expiredClaimCount,
    oldest_due_age_seconds: result.health.oldestDueAgeSeconds,
    generated_at: result.health.generatedAt,
  });
  if (result.healthStatus === "critical") {
    console.error(event);
  } else if (result.healthStatus === "warning") {
    console.warn(event);
  } else {
    console.log(event);
  }
}

export async function processRevenueCatReconciliations(
  supabaseAdmin: SupabaseClient,
  apiKey: string,
  dependencies: RevenueCatReconciliationDependencies = {},
): Promise<RevenueCatReconciliationResult> {
  const claim = dependencies.claim ?? claimRevenueCatReconciliations;
  const runtime = {
    fetchCustomerInfo: dependencies.fetchCustomerInfo ??
      fetchRevenueCatCustomerInfo,
    apply: dependencies.apply ?? applyRevenueCatReconciliation,
    fail: dependencies.fail ?? failRevenueCatReconciliation,
    health: dependencies.health ?? getRevenueCatReconciliationHealth,
    fetchImpl: dependencies.fetchImpl ?? fetch,
    now: dependencies.now ?? Date.now,
    monotonicNow: dependencies.monotonicNow ?? (() => performance.now()),
  };
  const startedAt = runtime.monotonicNow();
  if (!Number.isFinite(startedAt)) {
    throw new Error("RevenueCat reconciliation runtime clock is invalid.");
  }
  const claimCutoffAt = startedAt + RUNTIME_BUDGET_MS -
    FINAL_WAVE_AND_HEALTH_RESERVE_MS;
  const outcomes: Array<"applied" | "stale" | "failed"> = [];
  let claimed = 0;
  let claimBatches = 0;
  let claimLoopDrained = false;

  while (runtime.monotonicNow() < claimCutoffAt) {
    const claims = await claim(
      supabaseAdmin,
      CLAIM_BATCH_SIZE,
    );
    claimBatches += 1;
    if (claims.length === 0) {
      claimLoopDrained = true;
      break;
    }
    if (claims.length > CLAIM_BATCH_SIZE) {
      throw new Error(
        "RevenueCat reconciliation claim exceeded its requested batch size.",
      );
    }
    claimed += claims.length;

    for (let offset = 0; offset < claims.length; offset += FETCH_CONCURRENCY) {
      const batch = claims.slice(offset, offset + FETCH_CONCURRENCY);
      outcomes.push(
        ...await Promise.all(
          batch.map((item) =>
            reconcileOne(item, apiKey, supabaseAdmin, runtime)
          ),
        ),
      );
    }
  }

  const health = await runtime.health(supabaseAdmin);
  const healthStatus = revenueCatReconciliationHealthStatus(health);
  const queueDrained = health.dueCount === 0;
  const result: RevenueCatReconciliationResult = {
    claimed,
    reconciled: outcomes.filter((outcome) => outcome !== "failed").length,
    applied: outcomes.filter((outcome) => outcome === "applied").length,
    stale: outcomes.filter((outcome) => outcome === "stale").length,
    failed: outcomes.filter((outcome) => outcome === "failed").length,
    claimBatches,
    queueDrained,
    runtimeDeadlineReached: !claimLoopDrained && !queueDrained,
    healthStatus,
    health,
  };
  logReconciliationHealth(result);
  return result;
}
