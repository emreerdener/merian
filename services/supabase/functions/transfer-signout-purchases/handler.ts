import type { SupabaseClient, User } from "@supabase/supabase-js";
import { jsonResponse, logIdentitySafeError } from "../_shared/edgeHandler.ts";
import { publicErrorResponse } from "../_shared/http.ts";
import { readRequestJsonWithinBudget } from "../_shared/mediaBudgets.ts";
import { canonicalRevenueCatAppUserID } from "../_shared/revenuecatIdentity.ts";
import {
  applyRevenueCatReconciliation,
  claimRevenueCatReconciliationForUser,
  failRevenueCatReconciliation,
} from "../reconcile-revenuecat-subscribers/db.ts";
import {
  deriveRevenueCatStoreEntitlementState,
  fetchRevenueCatCustomerInfo,
  revenueCatAccessCovers,
  type RevenueCatCustomerInfo,
} from "../revenuecat-webhook/subscriber.ts";
import {
  bindSignoutPurchaseHandoff,
  cancelSignoutPurchaseHandoff,
  completeSignoutPurchaseHandoff,
  issueSignoutPurchaseHandoff,
  readSignoutPurchaseSourceEntitlement,
  SignoutPurchaseHandoffDatabaseError,
} from "./db.ts";
import {
  generateHandoffSecret,
  parseSignoutPurchaseHandoffRequest,
  sha256Hex,
  SIGNOUT_PURCHASE_HANDOFF_MAX_BODY_BYTES,
} from "./protocol.ts";

const MAX_SNAPSHOT_FUTURE_SKEW_MS = 5 * 60 * 1_000;
const MAX_SNAPSHOT_AGE_MS = 15 * 60 * 1_000;

export interface SignoutPurchaseHandoffDependencies {
  apiKey?: string;
  fetchCustomerInfo?: typeof fetchRevenueCatCustomerInfo;
  issueHandoff?: typeof issueSignoutPurchaseHandoff;
  readSourceEntitlement?: typeof readSignoutPurchaseSourceEntitlement;
  bindHandoff?: typeof bindSignoutPurchaseHandoff;
  cancelHandoff?: typeof cancelSignoutPurchaseHandoff;
  completeHandoff?: typeof completeSignoutPurchaseHandoff;
  claimReconciliation?: typeof claimRevenueCatReconciliationForUser;
  applyReconciliation?: typeof applyRevenueCatReconciliation;
  failReconciliation?: typeof failRevenueCatReconciliation;
  now?: () => number;
}

export async function handleSignoutPurchaseHandoff(
  req: Request,
  user: User,
  supabaseAdmin: SupabaseClient,
  dependencies: SignoutPurchaseHandoffDependencies = {},
): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const bodyResult = await readRequestJsonWithinBudget<unknown>(
    req,
    SIGNOUT_PURCHASE_HANDOFF_MAX_BODY_BYTES,
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

  const request = parseSignoutPurchaseHandoffRequest(bodyResult.value);
  if ("status" in request) {
    return jsonResponse(
      { code: request.code, error: request.message },
      request.status,
    );
  }

  const apiKey = (dependencies.apiKey ??
    Deno.env.get("REVENUECAT_SECRET_API_KEY") ?? "").trim();
  if (
    request.operation !== "bind" && request.operation !== "cancel" &&
    !apiKey.startsWith("sk_")
  ) {
    logIdentitySafeError("signout_purchase_handoff_configuration_invalid", {
      operation: request.operation,
      stage: "configuration",
      code: apiKey.length === 0 ? "secret_missing" : "secret_invalid",
    });
    return publicErrorResponse(
      req,
      503,
      "purchase_continuity_unavailable",
      "Purchase continuity is temporarily unavailable. Please try again.",
    );
  }

  const fetchCustomerInfo = dependencies.fetchCustomerInfo ??
    fetchRevenueCatCustomerInfo;
  const issueHandoff = dependencies.issueHandoff ??
    issueSignoutPurchaseHandoff;
  const readSourceEntitlement = dependencies.readSourceEntitlement ??
    readSignoutPurchaseSourceEntitlement;
  const bindHandoff = dependencies.bindHandoff ??
    bindSignoutPurchaseHandoff;
  const cancelHandoff = dependencies.cancelHandoff ??
    cancelSignoutPurchaseHandoff;
  const completeHandoff = dependencies.completeHandoff ??
    completeSignoutPurchaseHandoff;
  const claimReconciliation = dependencies.claimReconciliation ??
    claimRevenueCatReconciliationForUser;
  const applyReconciliation = dependencies.applyReconciliation ??
    applyRevenueCatReconciliation;
  const failReconciliation = dependencies.failReconciliation ??
    failRevenueCatReconciliation;
  const now = dependencies.now ?? Date.now;

  try {
    switch (request.operation) {
      case "prepare": {
        if (user.is_anonymous === true) {
          return jsonResponse(
            {
              code: "linked_session_required",
              error: "A linked account is required to prepare sign-out.",
            },
            403,
          );
        }

        const sourceInfo = await fetchCustomerInfo(
          canonicalRevenueCatAppUserID(user.id),
          apiKey,
        );
        validateSnapshotTime(sourceInfo, now());
        const storeAccessWithoutDetachedPass =
          deriveRevenueCatStoreEntitlementState(
            sourceInfo,
            false,
          );
        const expectedStoreAccess = deriveRevenueCatStoreEntitlementState(
          sourceInfo,
        );
        if (expectedStoreAccess.targetTier === "pro") {
          const sourceProjection = await readSourceEntitlement(
            supabaseAdmin,
            user.id,
          );
          if (!revenueCatAccessCovers(sourceProjection, expectedStoreAccess)) {
            return publicErrorResponse(
              req,
              503,
              "purchase_projection_pending",
              "Purchase access is still syncing. Please try sign-out again shortly.",
            );
          }

          // Detached seven-day passes remain in CustomerInfo after refund.
          // When the pass extends access beyond every entitlement-bound store
          // product, require the database's authoritative expiry to match it.
          if (
            !revenueCatAccessCovers(
              storeAccessWithoutDetachedPass,
              expectedStoreAccess,
            ) &&
            (sourceProjection.expiresAt === null ||
              expectedStoreAccess.expiresAt === null ||
              Date.parse(sourceProjection.expiresAt) !==
                Date.parse(expectedStoreAccess.expiresAt))
          ) {
            return publicErrorResponse(
              req,
              503,
              "purchase_projection_pending",
              "Purchase access is still syncing. Please try sign-out again shortly.",
            );
          }
        }
        const handoffSecret = generateHandoffSecret();
        const secretHash = await sha256Hex(handoffSecret);
        const handoff = await issueHandoff(
          supabaseAdmin,
          user.id,
          secretHash,
          sourceInfo.requestDateMs,
          expectedStoreAccess,
        );

        return jsonResponse(
          {
            success: true,
            handoff_id: handoff.handoffId,
            handoff_secret: handoffSecret,
            expires_at: handoff.expiresAt,
          },
          201,
          { "Cache-Control": "no-store", "Pragma": "no-cache" },
        );
      }

      case "bind": {
        if (user.is_anonymous !== true) {
          return jsonResponse(
            {
              code: "anonymous_session_required",
              error: "A signed-out session is required after sign-out.",
            },
            403,
          );
        }
        const bound = await bindHandoff(
          req,
          request.handoffId,
          await sha256Hex(request.handoffSecret),
        );
        if (bound.destinationUserId.toLowerCase() !== user.id.toLowerCase()) {
          throw new SignoutPurchaseHandoffDatabaseError(
            "handoff_identity_changed",
            503,
            "The signed-out session changed during purchase continuity.",
          );
        }
        return jsonResponse(
          {
            success: true,
            handoff_id: bound.handoffId,
            destination_user_id: bound.destinationUserId,
            bound_at: bound.boundAt,
            already_bound: bound.alreadyBound,
          },
          200,
        );
      }

      case "cancel": {
        if (user.is_anonymous === true) {
          return jsonResponse(
            {
              code: "linked_session_required",
              error: "The linked source session is required to cancel.",
            },
            403,
          );
        }
        const cancelled = await cancelHandoff(
          req,
          request.handoffId,
          await sha256Hex(request.handoffSecret),
        );
        return jsonResponse(
          {
            success: true,
            handoff_id: cancelled.handoffId,
            cancelled_at: cancelled.cancelledAt,
            already_cancelled: cancelled.alreadyCancelled,
          },
          200,
        );
      }

      case "complete": {
        if (user.is_anonymous !== true) {
          return jsonResponse(
            {
              code: "anonymous_session_required",
              error: "A signed-out session is required after sign-out.",
            },
            403,
          );
        }

        const secretHash = await sha256Hex(request.handoffSecret);
        const bound = await bindHandoff(
          req,
          request.handoffId,
          secretHash,
        );
        if (bound.destinationUserId.toLowerCase() !== user.id.toLowerCase()) {
          throw new SignoutPurchaseHandoffDatabaseError(
            "handoff_identity_changed",
            503,
            "The signed-out session changed during purchase continuity.",
          );
        }

        let destinationSnapshotAtMs = bound.destinationVerifiedSnapshotAtMs;
        let destinationVerifiedStoreAccess =
          bound.destinationVerifiedStoreAccess;
        if (bound.status === "bound") {
          // The client calls Purchases.syncPurchases() before this operation.
          // Verify the resulting custom destination from RevenueCat itself; the
          // caller cannot assert that a receipt moved successfully.
          const destinationInfo = await fetchCustomerInfo(
            canonicalRevenueCatAppUserID(user.id),
            apiKey,
          );
          validateSnapshotTime(destinationInfo, now());
          let destinationStoreAccess = deriveRevenueCatStoreEntitlementState(
            destinationInfo,
          );

          const preparedExpiresAtMs = bound.expectedStoreAccess.expiresAt ===
              null
            ? null
            : Date.parse(bound.expectedStoreAccess.expiresAt);
          const preparedFiniteHorizonElapsed = preparedExpiresAtMs !== null &&
            preparedExpiresAtMs <= destinationInfo.requestDateMs;

          // Re-read the source on every first completion. A renewal can land
          // after prepare but before the original horizon expires, and the
          // destination must cover that newer StoreKit state before completion.
          // The prepared horizon remains the floor until it naturally expires:
          // RevenueCat may retire the source customer as part of the receipt
          // move, which is not evidence that the purchase was refunded.
          let requiredStoreAccess = bound.expectedStoreAccess;
          if (preparedFiniteHorizonElapsed) {
            // A pass cannot renew, and purchase mutations are fenced while the
            // proof is pending. Exclude detached non-subscription history from
            // this post-expiry branch so an old refunded pass cannot be
            // mistaken for a new entitlement on either customer.
            destinationStoreAccess = deriveRevenueCatStoreEntitlementState(
              destinationInfo,
              false,
            );
            const sourceInfo = await fetchCustomerInfo(
              canonicalRevenueCatAppUserID(bound.sourceUserId),
              apiKey,
            );
            validateSnapshotTime(sourceInfo, now());
            requiredStoreAccess = deriveRevenueCatStoreEntitlementState(
              sourceInfo,
              false,
            );
          } else {
            const sourceInfo = await fetchCustomerInfo(
              canonicalRevenueCatAppUserID(bound.sourceUserId),
              apiKey,
            );
            validateSnapshotTime(sourceInfo, now());
            const currentSourceStoreAccess =
              deriveRevenueCatStoreEntitlementState(sourceInfo);
            if (
              !revenueCatAccessCovers(
                requiredStoreAccess,
                currentSourceStoreAccess,
              )
            ) {
              requiredStoreAccess = currentSourceStoreAccess;
            }
          }

          if (
            !revenueCatAccessCovers(destinationStoreAccess, requiredStoreAccess)
          ) {
            return publicErrorResponse(
              req,
              503,
              "purchase_transfer_pending",
              "Sign-out is complete, but purchase access is still syncing. Retrying is safe.",
            );
          }
          destinationSnapshotAtMs = destinationInfo.requestDateMs;
          destinationVerifiedStoreAccess = destinationStoreAccess;
        }

        if (
          destinationSnapshotAtMs === null ||
          destinationVerifiedStoreAccess === null
        ) {
          throw new SignoutPurchaseHandoffDatabaseError(
            "handoff_invalid_response",
            503,
            "Purchase continuity is temporarily unavailable. Retrying is safe.",
          );
        }

        const completed = await completeHandoff(
          supabaseAdmin,
          request.handoffId,
          secretHash,
          user.id,
          destinationSnapshotAtMs,
          destinationVerifiedStoreAccess,
        );

        const claim = await claimReconciliation(
          supabaseAdmin,
          user.id,
        );
        try {
          if (
            claim.lookupAppUserId !== canonicalRevenueCatAppUserID(user.id)
          ) {
            throw new Error(
              "Sign-out reconciliation selected a non-canonical destination.",
            );
          }
          // Apply the immutable destination snapshot attested above. Freshness
          // and source-coverage checks ensure this is the receipt that was just
          // synchronized, while Store provenance excludes promotions.
          const entitlement = destinationVerifiedStoreAccess;
          await applyReconciliation(
            claim,
            destinationSnapshotAtMs,
            entitlement.targetTier,
            entitlement.expiresAt,
            supabaseAdmin,
          );
        } catch (error) {
          try {
            await failReconciliation(
              claim,
              "signout_handoff_foreground_reconciliation_failed",
              supabaseAdmin,
            );
          } catch (failureWriteError) {
            logIdentitySafeError(
              "signout_purchase_handoff_failure_persistence_failed",
              {
                operation: request.operation,
                stage: "persist_failure",
                code: safeErrorName(failureWriteError),
              },
            );
          }
          throw error;
        }

        return jsonResponse(
          {
            success: true,
            handoff_id: completed.handoffId,
            completed_at: completed.completedAt,
            already_completed: completed.alreadyCompleted,
          },
          200,
        );
      }
    }
  } catch (error) {
    if (error instanceof SignoutPurchaseHandoffDatabaseError) {
      logIdentitySafeError("signout_purchase_handoff_rejected", {
        operation: request.operation,
        stage: "database",
        code: error.code,
        status: error.status,
      });
      return publicErrorResponse(
        req,
        error.status,
        error.code,
        error.message,
      );
    }

    logIdentitySafeError("signout_purchase_handoff_failed", {
      operation: request.operation,
      stage: "processing",
      code: safeErrorName(error),
    });
    return publicErrorResponse(
      req,
      503,
      "purchase_continuity_unavailable",
      "Purchase continuity is temporarily unavailable. Retrying is safe.",
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
