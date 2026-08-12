import type { SupabaseClient, User } from "@supabase/supabase-js";
import { jsonResponse, logStructuredError } from "../_shared/edgeHandler.ts";
import { publicErrorResponse } from "../_shared/http.ts";
import { readRequestJsonWithinBudget } from "../_shared/mediaBudgets.ts";
import {
  deriveRevenueCatAccountGrantState,
  deriveRevenueCatStoreEntitlementState,
  fetchRevenueCatCustomerInfo,
  revenueCatAccessCovers,
  type RevenueCatCustomerInfo,
} from "../revenuecat-webhook/subscriber.ts";
import {
  beginPurchasePrincipalResolution,
  completePurchasePrincipalResolution,
  PurchasePrincipalDatabaseError,
  readCurrentEntitlementProjection,
} from "./db.ts";
import {
  parseResolvePurchasePrincipalRequest,
  PURCHASE_PRINCIPAL_MAX_BODY_BYTES,
  sha256Hex,
} from "./protocol.ts";

const MAX_SNAPSHOT_FUTURE_SKEW_MS = 5 * 60 * 1_000;
const MAX_SNAPSHOT_AGE_MS = 15 * 60 * 1_000;

export interface PurchasePrincipalResolverDependencies {
  apiKey?: string;
  begin?: typeof beginPurchasePrincipalResolution;
  complete?: typeof completePurchasePrincipalResolution;
  readCurrentEntitlement?: typeof readCurrentEntitlementProjection;
  fetchCustomerInfo?: typeof fetchRevenueCatCustomerInfo;
  now?: () => number;
}

export async function handleResolvePurchasePrincipal(
  req: Request,
  user: User,
  supabaseAdmin: SupabaseClient,
  dependencies: PurchasePrincipalResolverDependencies = {},
): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse(
      { code: "method_not_allowed", error: "Method not allowed." },
      405,
      {
        Allow: "POST",
      },
    );
  }

  const bodyResult = await readRequestJsonWithinBudget<unknown>(
    req,
    PURCHASE_PRINCIPAL_MAX_BODY_BYTES,
  );
  if (bodyResult.error || bodyResult.value === undefined) {
    return jsonResponse(
      {
        code: "invalid_request",
        error: bodyResult.error?.message ?? "Invalid JSON body.",
      },
      bodyResult.error?.status ?? 400,
    );
  }
  const request = parseResolvePurchasePrincipalRequest(bodyResult.value);
  if ("status" in request) {
    return jsonResponse(
      { code: request.code, error: request.message },
      request.status,
    );
  }

  const begin = dependencies.begin ?? beginPurchasePrincipalResolution;
  const complete = dependencies.complete ?? completePurchasePrincipalResolution;
  const fetchCustomerInfo = dependencies.fetchCustomerInfo ??
    fetchRevenueCatCustomerInfo;
  const now = dependencies.now ?? Date.now;
  const capabilityHash = await sha256Hex(request.installationCapability);

  try {
    const start = await begin(
      supabaseAdmin,
      user.id,
      capabilityHash,
      request.clientProtocol,
      request.bindingIntentGeneration,
    );
    if (start.mode === "legacy") {
      return jsonResponse(
        {
          success: true,
          mode: "legacy",
          minimum_client_protocol: start.minimumClientProtocol,
        },
        200,
        { "Cache-Control": "no-store", "Pragma": "no-cache" },
      );
    }

    const apiKey = (dependencies.apiKey ??
      Deno.env.get("REVENUECAT_SECRET_API_KEY") ?? "").trim();
    if (!apiKey.startsWith("sk_")) {
      logStructuredError("purchase_principal_configuration_invalid", {
        reason: apiKey.length === 0 ? "secret_missing" : "secret_invalid",
      });
      return publicErrorResponse(
        req,
        503,
        "purchase_principal_unavailable",
        "Purchase access is temporarily unavailable. Please try again.",
        { retryAfterSeconds: 30 },
      );
    }

    const customerInfo = await fetchCustomerInfo(
      start.revenueCatAppUserId,
      apiKey,
    );
    validateSnapshotTime(customerInfo, now());
    const storeWithoutDetachedPass = deriveRevenueCatStoreEntitlementState(
      customerInfo,
      false,
    );
    const storeWithDetachedPass = deriveRevenueCatStoreEntitlementState(
      customerInfo,
      true,
    );
    let allowNonSubscriptionPassGrant = start.allowNonSubscriptionPassGrant;
    if (allowNonSubscriptionPassGrant === null) {
      allowNonSubscriptionPassGrant = false;
      if (
        !revenueCatAccessCovers(
          storeWithoutDetachedPass,
          storeWithDetachedPass,
        )
      ) {
        const currentProjection = await (
          dependencies.readCurrentEntitlement ??
            readCurrentEntitlementProjection
        )(supabaseAdmin, user.id);
        allowNonSubscriptionPassGrant =
          currentProjection.targetTier === "pro" &&
          currentProjection.expiresAt !== null &&
          storeWithDetachedPass.expiresAt !== null &&
          Date.parse(currentProjection.expiresAt) ===
            Date.parse(storeWithDetachedPass.expiresAt);
      }
    }
    const storeState = allowNonSubscriptionPassGrant
      ? storeWithDetachedPass
      : storeWithoutDetachedPass;
    const binding = await complete(
      supabaseAdmin,
      user.id,
      start,
      capabilityHash,
      customerInfo.requestDateMs,
      storeState,
      allowNonSubscriptionPassGrant,
      deriveRevenueCatAccountGrantState(customerInfo),
    );

    return jsonResponse(
      {
        success: true,
        mode: "stable",
        purchase_principal_id: binding.purchasePrincipalId,
        revenuecat_app_user_id: binding.revenueCatAppUserId,
        binding_generation: binding.bindingGeneration,
        account_grants_allowed: binding.accountGrantsAllowed,
        minimum_client_protocol: start.minimumClientProtocol,
      },
      200,
      { "Cache-Control": "no-store", "Pragma": "no-cache" },
    );
  } catch (error) {
    if (error instanceof PurchasePrincipalDatabaseError) {
      logStructuredError("purchase_principal_resolution_rejected", {
        code: error.code,
        retryable: error.retryable,
      });
      if (error.code === "purchase_principal_client_upgrade_required") {
        return publicErrorResponse(
          req,
          426,
          error.code,
          "Update Merian to keep purchase access connected.",
        );
      }
      return publicErrorResponse(
        req,
        error.retryable ? 503 : 409,
        error.code,
        error.retryable
          ? "Purchase access is temporarily unavailable. Please try again."
          : "This installation can no longer use its saved purchase identity.",
        { retryAfterSeconds: error.retryable ? 30 : undefined },
      );
    }

    logStructuredError("purchase_principal_resolution_failed", {
      failure_name: safeErrorName(error),
    });
    return publicErrorResponse(
      req,
      503,
      "purchase_principal_unavailable",
      "Purchase access is temporarily unavailable. Please try again.",
      { retryAfterSeconds: 30 },
    );
  }
}

function validateSnapshotTime(
  customerInfo: RevenueCatCustomerInfo,
  nowMs: number,
): void {
  if (
    !Number.isFinite(nowMs) ||
    customerInfo.requestDateMs > nowMs + MAX_SNAPSHOT_FUTURE_SKEW_MS ||
    customerInfo.requestDateMs < nowMs - MAX_SNAPSHOT_AGE_MS
  ) {
    throw new Error("RevenueCat snapshot timestamp is invalid.");
  }
}

function safeErrorName(error: unknown): string {
  const candidate = error instanceof Error ? error.name : typeof error;
  return /^[A-Za-z][A-Za-z0-9]{0,63}$/.test(candidate)
    ? candidate
    : "UnknownFailure";
}
