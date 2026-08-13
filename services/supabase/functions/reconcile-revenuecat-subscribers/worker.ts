import { SupabaseClient } from "@supabase/supabase-js";
import {
  deriveRevenueCatAccountGrantState,
  deriveRevenueCatEntitlementState,
  deriveRevenueCatStoreEntitlementState,
  fetchRevenueCatCustomerInfo,
} from "../revenuecat-webhook/subscriber.ts";
import {
  applyPurchasePrincipalReconciliation,
  applyRevenueCatReconciliation,
  claimPurchasePrincipalReconciliations,
  claimRevenueCatReconciliations,
  failPurchasePrincipalReconciliation,
  failRevenueCatReconciliation,
  getPurchasePrincipalHealth,
  getRevenueCatReconciliationHealth,
  PurchasePrincipalHealth,
  PurchasePrincipalReconciliationClaim,
  RevenueCatReconciliationClaim,
  RevenueCatReconciliationHealth,
} from "./db.ts";
import { logIdentitySafeError } from "../_shared/edgeHandler.ts";

const FETCH_CONCURRENCY = 3;
// The worker drains two independent identity queues. Three claims per lane
// keep one combined wave at six provider calls, so two concurrency rounds fit
// inside the 30-second final-wave reserve even when every RevenueCat request
// reaches its ten-second fetch deadline.
const CLAIM_BATCH_SIZE_PER_IDENTITY = 3;
const RUNTIME_BUDGET_MS = 90_000;
const FINAL_WAVE_AND_HEALTH_RESERVE_MS = 30_000;
const MAX_SNAPSHOT_FUTURE_SKEW_MS = 5 * 60 * 1_000;
const MAX_SNAPSHOT_AGE_MS = 15 * 60 * 1_000;
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
  purchasePrincipalHealth: PurchasePrincipalHealth;
}

interface RevenueCatReconciliationDependencies {
  claim?: typeof claimRevenueCatReconciliations;
  claimPrincipal?: typeof claimPurchasePrincipalReconciliations;
  fetchCustomerInfo?: typeof fetchRevenueCatCustomerInfo;
  apply?: typeof applyRevenueCatReconciliation;
  applyPrincipal?: typeof applyPurchasePrincipalReconciliation;
  fail?: typeof failRevenueCatReconciliation;
  failPrincipal?: typeof failPurchasePrincipalReconciliation;
  health?: typeof getRevenueCatReconciliationHealth;
  principalHealth?: typeof getPurchasePrincipalHealth;
  fetchImpl?: typeof fetch;
  now?: () => number;
  monotonicNow?: () => number;
}

const EMPTY_PURCHASE_PRINCIPAL_HEALTH: PurchasePrincipalHealth = {
  generatedAt: new Date(0).toISOString(),
  activePrincipalCount: 0,
  pendingPrincipalCount: 0,
  unboundActivePrincipalCount: 0,
  dueReconciliationCount: 0,
  expiredClaimCount: 0,
  oldestDueAt: null,
  oldestDueAgeSeconds: null,
  oldestPendingAt: null,
  oldestPendingAgeSeconds: null,
};

function publicFailureCode(error: unknown): string {
  if (!(error instanceof Error)) return "reconciliation_failed";
  switch (error.name) {
    case "AbortError":
      return "provider_request_aborted";
    case "TimeoutError":
      return "provider_request_timed_out";
    case "TypeError":
      return "dependency_type_error";
    default:
      return "reconciliation_failed";
  }
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
    const observedAtMs = dependencies.now();
    if (
      customerInfo.requestDateMs >
        observedAtMs + MAX_SNAPSHOT_FUTURE_SKEW_MS ||
      customerInfo.requestDateMs < observedAtMs - MAX_SNAPSHOT_AGE_MS
    ) {
      throw new Error(
        "RevenueCat snapshot timestamp is outside the accepted window.",
      );
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
    logIdentitySafeError("revenuecat_reconciliation_failed", {
      identityKind: "legacy",
      stage: "reconcile",
      code: publicFailureCode(error),
    });
    try {
      await dependencies.fail(
        claim,
        publicFailureCode(error),
        supabaseAdmin,
      );
    } catch (failureWriteError) {
      logIdentitySafeError("revenuecat_reconciliation_failure_write_failed", {
        identityKind: "legacy",
        stage: "persist_failure",
        code: publicFailureCode(failureWriteError),
      });
    }
    return "failed";
  }
}

async function reconcilePrincipalOne(
  claim: PurchasePrincipalReconciliationClaim,
  apiKey: string,
  supabaseAdmin: SupabaseClient,
  dependencies: Required<
    Pick<
      RevenueCatReconciliationDependencies,
      | "fetchCustomerInfo"
      | "applyPrincipal"
      | "failPrincipal"
      | "fetchImpl"
      | "now"
    >
  >,
): Promise<"applied" | "stale" | "failed"> {
  try {
    const customerInfo = await dependencies.fetchCustomerInfo(
      claim.lookupAppUserId,
      apiKey,
      dependencies.fetchImpl,
    );
    const observedAtMs = dependencies.now();
    if (
      customerInfo.requestDateMs >
        observedAtMs + MAX_SNAPSHOT_FUTURE_SKEW_MS ||
      customerInfo.requestDateMs < observedAtMs - MAX_SNAPSHOT_AGE_MS
    ) {
      throw new Error(
        "RevenueCat snapshot timestamp is outside the accepted window.",
      );
    }
    const storeState = deriveRevenueCatStoreEntitlementState(
      customerInfo,
      claim.allowNonSubscriptionPassGrant,
    );
    const accountGrantState = deriveRevenueCatAccountGrantState(customerInfo);
    const applied = await dependencies.applyPrincipal(
      claim,
      customerInfo.requestDateMs,
      storeState.targetTier,
      storeState.expiresAt,
      accountGrantState.targetTier,
      accountGrantState.expiresAt,
      supabaseAdmin,
    );
    return applied ? "applied" : "stale";
  } catch (error) {
    logIdentitySafeError("revenuecat_reconciliation_failed", {
      identityKind: "purchase_principal",
      stage: "reconcile",
      code: publicFailureCode(error),
    });
    try {
      await dependencies.failPrincipal(
        claim,
        publicFailureCode(error),
        supabaseAdmin,
      );
    } catch (failureWriteError) {
      logIdentitySafeError("revenuecat_reconciliation_failure_write_failed", {
        identityKind: "purchase_principal",
        stage: "persist_failure",
        code: publicFailureCode(failureWriteError),
      });
    }
    return "failed";
  }
}

export function revenueCatReconciliationHealthStatus(
  health: RevenueCatReconciliationHealth,
  principalHealth: PurchasePrincipalHealth = EMPTY_PURCHASE_PRINCIPAL_HEALTH,
): RevenueCatReconciliationHealthStatus {
  const oldestDueAgeSeconds = Math.max(
    health.oldestDueAgeSeconds ?? 0,
    health.oldestSignoutPendingAgeSeconds ?? 0,
    principalHealth.oldestDueAgeSeconds ?? 0,
    principalHealth.oldestPendingAgeSeconds ?? 0,
  );
  if (oldestDueAgeSeconds >= BACKLOG_CRITICAL_AGE_SECONDS) {
    return "critical";
  }
  if (
    health.expiredClaimCount > 0 || principalHealth.expiredClaimCount > 0 ||
    principalHealth.unboundActivePrincipalCount > 0 ||
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
    signout_prepared_count: result.health.signoutPreparedCount,
    signout_bound_count: result.health.signoutBoundCount,
    oldest_signout_pending_age_seconds:
      result.health.oldestSignoutPendingAgeSeconds,
    generated_at: result.health.generatedAt,
    purchase_principal_active_count:
      result.purchasePrincipalHealth.activePrincipalCount,
    purchase_principal_pending_count:
      result.purchasePrincipalHealth.pendingPrincipalCount,
    purchase_principal_unbound_active_count:
      result.purchasePrincipalHealth.unboundActivePrincipalCount,
    purchase_principal_due_count:
      result.purchasePrincipalHealth.dueReconciliationCount,
    purchase_principal_expired_claim_count:
      result.purchasePrincipalHealth.expiredClaimCount,
    purchase_principal_oldest_due_age_seconds:
      result.purchasePrincipalHealth.oldestDueAgeSeconds,
    purchase_principal_oldest_pending_age_seconds:
      result.purchasePrincipalHealth.oldestPendingAgeSeconds,
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
  const claimPrincipal = dependencies.claimPrincipal ??
    claimPurchasePrincipalReconciliations;
  const runtime = {
    fetchCustomerInfo: dependencies.fetchCustomerInfo ??
      fetchRevenueCatCustomerInfo,
    apply: dependencies.apply ?? applyRevenueCatReconciliation,
    applyPrincipal: dependencies.applyPrincipal ??
      applyPurchasePrincipalReconciliation,
    fail: dependencies.fail ?? failRevenueCatReconciliation,
    failPrincipal: dependencies.failPrincipal ??
      failPurchasePrincipalReconciliation,
    health: dependencies.health ?? getRevenueCatReconciliationHealth,
    principalHealth: dependencies.principalHealth ?? getPurchasePrincipalHealth,
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
    const [claims, principalClaims] = await Promise.all([
      claim(supabaseAdmin, CLAIM_BATCH_SIZE_PER_IDENTITY),
      claimPrincipal(supabaseAdmin, CLAIM_BATCH_SIZE_PER_IDENTITY),
    ]);
    claimBatches += 1;
    if (claims.length === 0 && principalClaims.length === 0) {
      claimLoopDrained = true;
      break;
    }
    if (
      claims.length > CLAIM_BATCH_SIZE_PER_IDENTITY ||
      principalClaims.length > CLAIM_BATCH_SIZE_PER_IDENTITY
    ) {
      throw new Error(
        "RevenueCat reconciliation claim exceeded its requested batch size.",
      );
    }
    claimed += claims.length + principalClaims.length;

    const work = [
      ...claims.map((claim) => ({ kind: "legacy" as const, claim })),
      ...principalClaims.map((claim) => ({
        kind: "purchase_principal" as const,
        claim,
      })),
    ];
    for (let offset = 0; offset < work.length; offset += FETCH_CONCURRENCY) {
      const batch = work.slice(offset, offset + FETCH_CONCURRENCY);
      outcomes.push(
        ...await Promise.all(
          batch.map((item) =>
            item.kind === "legacy"
              ? reconcileOne(item.claim, apiKey, supabaseAdmin, runtime)
              : reconcilePrincipalOne(
                item.claim,
                apiKey,
                supabaseAdmin,
                runtime,
              )
          ),
        ),
      );
    }
  }

  const [health, purchasePrincipalHealth] = await Promise.all([
    runtime.health(supabaseAdmin),
    runtime.principalHealth(supabaseAdmin),
  ]);
  const healthStatus = revenueCatReconciliationHealthStatus(
    health,
    purchasePrincipalHealth,
  );
  const queueDrained = health.dueCount === 0 &&
    purchasePrincipalHealth.dueReconciliationCount === 0;
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
    purchasePrincipalHealth,
  };
  logReconciliationHealth(result);
  return result;
}
