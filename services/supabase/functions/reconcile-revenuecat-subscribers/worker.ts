import { SupabaseClient } from "@supabase/supabase-js";
import {
  deriveRevenueCatEntitlementState,
  fetchRevenueCatCustomerInfo,
} from "../revenuecat-webhook/subscriber.ts";
import {
  applyRevenueCatReconciliation,
  claimRevenueCatReconciliations,
  failRevenueCatReconciliation,
  RevenueCatReconciliationClaim,
} from "./db.ts";

const MAX_CLAIMS_PER_INVOCATION = 10;
const FETCH_CONCURRENCY = 3;
const MAX_SNAPSHOT_FUTURE_SKEW_MS = 5 * 60 * 1_000;

export interface RevenueCatReconciliationResult {
  claimed: number;
  reconciled: number;
  applied: number;
  stale: number;
  failed: number;
}

interface RevenueCatReconciliationDependencies {
  claim?: typeof claimRevenueCatReconciliations;
  fetchCustomerInfo?: typeof fetchRevenueCatCustomerInfo;
  apply?: typeof applyRevenueCatReconciliation;
  fail?: typeof failRevenueCatReconciliation;
  fetchImpl?: typeof fetch;
  now?: () => number;
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
    fetchImpl: dependencies.fetchImpl ?? fetch,
    now: dependencies.now ?? Date.now,
  };
  const claims = await claim(
    supabaseAdmin,
    MAX_CLAIMS_PER_INVOCATION,
  );
  const outcomes: Array<"applied" | "stale" | "failed"> = [];

  for (let offset = 0; offset < claims.length; offset += FETCH_CONCURRENCY) {
    const batch = claims.slice(offset, offset + FETCH_CONCURRENCY);
    outcomes.push(
      ...await Promise.all(
        batch.map((item) => reconcileOne(item, apiKey, supabaseAdmin, runtime)),
      ),
    );
  }

  return {
    claimed: claims.length,
    reconciled: outcomes.filter((outcome) => outcome !== "failed").length,
    applied: outcomes.filter((outcome) => outcome === "applied").length,
    stale: outcomes.filter((outcome) => outcome === "stale").length,
    failed: outcomes.filter((outcome) => outcome === "failed").length,
  };
}
