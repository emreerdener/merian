import { SupabaseClient } from "@supabase/supabase-js";
import { jsonResponse, logIdentitySafeError } from "../_shared/edgeHandler.ts";
import {
  isJsonMediaType,
  publicErrorResponse,
  readRequestBodyWithinLimit,
  requestIdFor,
  timingSafeCompare,
} from "../_shared/http.ts";
import {
  applyRevenueCatIdentityState,
  getRevenueCatWebhookEventResult,
  resolveRevenueCatIdentitySubjects,
  RevenueCatDatabaseError,
  scheduleRevenueCatIdentityReconciliation,
} from "./db.ts";
import {
  MAX_REVENUECAT_WEBHOOK_BYTES,
  parseRevenueCatWebhook,
  RevenueCatPayloadError,
  revenueCatWebhookSubjects,
} from "./protocol.ts";
import {
  REVENUECAT_SIGNATURE_TOLERANCE_SECONDS,
  sha256Hex,
  verifyRevenueCatSignature,
} from "./signature.ts";
import {
  deriveRevenueCatAccountGrantState,
  deriveRevenueCatEntitlementState,
  deriveRevenueCatStoreEntitlementState,
  fetchRevenueCatCustomerInfo,
  hasActiveRevenueCatAppStorePass,
  RevenueCatApiError,
  revenueCatNonSubscriptionPassGrantDecision,
} from "./subscriber.ts";

const MAX_CUSTOMER_INFO_AGE_MS = 15 * 60 * 1_000;

export interface RevenueCatWebhookConfig {
  authorizationSecret: string;
  signingSecret: string;
  apiKey: string;
}

export interface RevenueCatWebhookDependencies {
  supabaseAdmin: SupabaseClient;
  config: RevenueCatWebhookConfig;
  fetchImpl?: typeof fetch;
  now?: () => number;
}

function configurationIsComplete(config: RevenueCatWebhookConfig): boolean {
  return config.authorizationSecret.length >= 32 &&
    config.signingSecret.length >= 32 &&
    config.apiKey.startsWith("sk_");
}

function databaseErrorIsRetryable(code: string | null): boolean {
  return code === null ||
    code.startsWith("08") ||
    ["40001", "40P01", "53300", "57014", "57P01", "P0001"].includes(code);
}

export function createRevenueCatWebhookHandler(
  dependencies: RevenueCatWebhookDependencies,
): (request: Request) => Promise<Response> {
  const fetchImpl = dependencies.fetchImpl ?? fetch;
  const now = dependencies.now ?? Date.now;

  return async (request: Request): Promise<Response> => {
    const requestId = requestIdFor(request);
    if (request.method !== "POST") {
      return publicErrorResponse(
        request,
        405,
        "method_not_allowed",
        "Method not allowed.",
        { extraHeaders: { Allow: "POST" } },
      );
    }

    if (!configurationIsComplete(dependencies.config)) {
      logIdentitySafeError("revenuecat_webhook_configuration_invalid", {
        stage: "configuration",
        code: "missing_configuration",
      });
      return publicErrorResponse(
        request,
        503,
        "service_unavailable",
        "The service is temporarily unavailable.",
      );
    }

    const authorization = request.headers.get("Authorization") ?? "";
    if (
      !timingSafeCompare(
        authorization,
        `Bearer ${dependencies.config.authorizationSecret}`,
      )
    ) {
      return publicErrorResponse(
        request,
        401,
        "unauthorized",
        "Unauthorized.",
      );
    }

    if (!isJsonMediaType(request.headers.get("content-type"))) {
      return publicErrorResponse(
        request,
        415,
        "unsupported_media_type",
        "Content-Type must be application/json.",
      );
    }

    const bodyResult = await readRequestBodyWithinLimit(
      request,
      MAX_REVENUECAT_WEBHOOK_BYTES,
    );
    if (bodyResult.error || !bodyResult.bytes) {
      const error = bodyResult.error ?? {
        status: 400,
        code: "invalid_json",
        message: "Invalid request body.",
      };
      return publicErrorResponse(
        request,
        error.status,
        error.code,
        error.message,
      );
    }
    const rawBytes = bodyResult.bytes;

    let verifiedSignature;
    try {
      verifiedSignature = await verifyRevenueCatSignature(
        request.headers.get("X-RevenueCat-Webhook-Signature"),
        dependencies.config.signingSecret,
        rawBytes,
        now(),
      );
    } catch {
      logIdentitySafeError("revenuecat_webhook_signature_failed", {
        stage: "signature",
        code: "verification_unavailable",
      });
      return publicErrorResponse(
        request,
        503,
        "signature_verification_unavailable",
        "The service is temporarily unavailable.",
      );
    }
    if (!verifiedSignature) {
      return publicErrorResponse(
        request,
        401,
        "invalid_webhook_signature",
        "Unauthorized.",
      );
    }

    try {
      let rawBody: string;
      try {
        rawBody = new TextDecoder("utf-8", { fatal: true }).decode(rawBytes);
      } catch {
        throw new RevenueCatPayloadError("Invalid UTF-8 JSON.");
      }
      const event = parseRevenueCatWebhook(rawBody);
      if (
        event.eventTimestampMs >
          (verifiedSignature.timestampSeconds +
              REVENUECAT_SIGNATURE_TOLERANCE_SECONDS) * 1_000
      ) {
        throw new RevenueCatPayloadError(
          "event_timestamp_ms is implausibly far in the future.",
        );
      }
      const payloadSha256 = await sha256Hex(rawBytes);
      const subjects = revenueCatWebhookSubjects(event);
      const identitySubjects = subjects.map((subject) => ({
        kind: subject.kind,
        identifiers: subject.identifiers,
      }));

      const existingResult = await getRevenueCatWebhookEventResult(
        event.id,
        event.eventTimestampMs,
        event.type,
        payloadSha256,
        dependencies.supabaseAdmin,
      );
      if (existingResult) {
        // The first delivery may have committed the entitlement transaction and
        // crashed before queuing periodic reconciliation. Repair that gap on
        // every durable duplicate before acknowledging it.
        try {
          const duplicateSubjects = await resolveRevenueCatIdentitySubjects(
            identitySubjects,
            dependencies.supabaseAdmin,
          );
          await scheduleRevenueCatIdentityReconciliation(
            duplicateSubjects,
            dependencies.supabaseAdmin,
          );
        } catch (error) {
          if (
            !(error instanceof RevenueCatDatabaseError) ||
            !error.message.includes("revenuecat_user_not_found")
          ) {
            throw error;
          }
          // A committed event remains a valid duplicate after its profile was
          // deleted; there is no live reconciliation destination to repair.
        }
        console.info(JSON.stringify({
          event: "revenuecat_webhook_processed",
          outcome: "duplicate",
          subject_count: existingResult.subjectCount,
          applied_count: existingResult.appliedCount,
          stale_count: existingResult.staleCount,
        }));
        return jsonResponse(
          {
            success: true,
            outcome: "duplicate",
            subject_count: existingResult.subjectCount,
            applied_count: existingResult.appliedCount,
            stale_count: existingResult.staleCount,
          },
          200,
          { "X-Request-ID": requestId },
        );
      }

      const resolvedSubjects = await resolveRevenueCatIdentitySubjects(
        identitySubjects,
        dependencies.supabaseAdmin,
      );

      // RevenueCat recommends fetching CustomerInfo after each webhook. The
      // event itself is a synchronization signal, never the entitlement truth.
      // A committed duplicate and an event with no resolved Merian identity are the only
      // safe provider-lookup bypasses. TRANSFER reconciles both sides before
      // one database transaction so it can never half-move access.
      const fetchedSubjects = await Promise.all(
        resolvedSubjects.map(async (subject) => {
          const customerInfo = await fetchRevenueCatCustomerInfo(
            subject.lookupAppUserId,
            dependencies.config.apiKey,
            fetchImpl,
          );
          const observedAtMs = now();
          if (
            customerInfo.requestDateMs >
              observedAtMs +
                REVENUECAT_SIGNATURE_TOLERANCE_SECONDS * 1_000 ||
            customerInfo.requestDateMs <
              observedAtMs - MAX_CUSTOMER_INFO_AGE_MS
          ) {
            throw new RevenueCatApiError(
              "RevenueCat CustomerInfo snapshot timestamp is outside the accepted window.",
              true,
            );
          }
          return { subject, customerInfo };
        }),
      );
      const transferSource = event.type === "TRANSFER"
        ? fetchedSubjects.find(({ subject }) =>
          subject.kind === "transfer_source" &&
          subject.identityKind === "purchase_principal"
        ) ?? null
        : null;
      const transferSourcePassPolicy =
        transferSource?.subject.allowNonSubscriptionPassGrant ?? null;
      const transferSourceHasActivePass = transferSourcePassPolicy === true &&
        transferSource !== null &&
        hasActiveRevenueCatAppStorePass(transferSource.customerInfo);
      const stateSubjects = fetchedSubjects.map(
        ({ subject, customerInfo }) => {
          let passGrantPolicyUpdate =
            subject.identityKind === "purchase_principal"
              ? revenueCatNonSubscriptionPassGrantDecision(
                customerInfo,
                event,
                subject.kind,
              )
              : null;
          if (
            event.type === "TRANSFER" &&
            subject.identityKind === "purchase_principal" &&
            subject.kind === "transfer_destination" &&
            transferSourcePassPolicy === true &&
            (transferSourceHasActivePass ||
              hasActiveRevenueCatAppStorePass(customerInfo))
          ) {
            if (!hasActiveRevenueCatAppStorePass(customerInfo)) {
              // RevenueCat may deliver TRANSFER before the destination's
              // CustomerInfo projection catches up. Retrying is safer than
              // granting permission to unrelated historical pass records.
              throw new RevenueCatApiError(
                "RevenueCat transfer destination did not include the active App Store pass.",
                true,
              );
            }
            passGrantPolicyUpdate = true;
          }
          const storeState = subject.identityKind === "purchase_principal"
            ? deriveRevenueCatStoreEntitlementState(
              customerInfo,
              passGrantPolicyUpdate ??
                subject.allowNonSubscriptionPassGrant ?? false,
              event,
            )
            : deriveRevenueCatEntitlementState(customerInfo, event);
          const accountGrantState =
            subject.identityKind === "purchase_principal"
              ? deriveRevenueCatAccountGrantState(customerInfo)
              : { targetTier: "free" as const, expiresAt: null };
          return {
            ...subject,
            authoritativeSnapshotAtMs: customerInfo.requestDateMs,
            targetStoreTier: storeState.targetTier,
            targetStoreExpiresAt: storeState.expiresAt,
            targetAccountGrantTier: accountGrantState.targetTier,
            targetAccountGrantExpiresAt: accountGrantState.expiresAt,
            passGrantPolicyUpdate,
          };
        },
      );

      const result = await applyRevenueCatIdentityState(
        {
          eventId: event.id,
          eventTimestampMs: event.eventTimestampMs,
          eventType: event.type,
          payloadSha256,
          signatureTimestampSeconds: verifiedSignature.timestampSeconds,
          subjects: stateSubjects,
        },
        dependencies.supabaseAdmin,
      );
      await scheduleRevenueCatIdentityReconciliation(
        resolvedSubjects,
        dependencies.supabaseAdmin,
      );

      console.info(JSON.stringify({
        event: "revenuecat_webhook_processed",
        outcome: result.outcome,
        applied_count: result.appliedCount,
        stale_count: result.staleCount,
        subject_count: result.subjectCount,
      }));
      return jsonResponse(
        {
          success: true,
          outcome: result.outcome,
          subject_count: result.subjectCount,
          applied_count: result.appliedCount,
          stale_count: result.staleCount,
        },
        200,
        { "X-Request-ID": requestId },
      );
    } catch (error) {
      if (error instanceof RevenueCatPayloadError) {
        return publicErrorResponse(
          request,
          400,
          "invalid_webhook_payload",
          "Invalid webhook payload.",
        );
      }

      if (error instanceof RevenueCatApiError) {
        logIdentitySafeError("revenuecat_webhook_provider_failed", {
          stage: "provider_lookup",
          code: error.retryable ? "retryable" : "terminal",
          status: error.retryable ? 503 : 502,
        });
        return publicErrorResponse(
          request,
          error.retryable ? 503 : 502,
          "entitlement_lookup_failed",
          "Authoritative entitlement lookup failed.",
          { retryAfterSeconds: error.retryable ? 30 : undefined },
        );
      }

      if (error instanceof RevenueCatDatabaseError) {
        logIdentitySafeError("revenuecat_webhook_database_failed", {
          stage: "database_transition",
          code: error.code ?? "unknown",
        });
        if (error.message.includes("revenuecat_user_not_found")) {
          return publicErrorResponse(
            request,
            503,
            "user_profile_not_ready",
            "User profile is not ready.",
            { retryAfterSeconds: 30 },
          );
        }
        if (error.message.includes("revenuecat_event_id_conflict")) {
          return publicErrorResponse(
            request,
            409,
            "event_identifier_conflict",
            "Event identifier conflict.",
          );
        }
        if (
          error.message.includes("revenuecat_user_mapping_ambiguous") ||
          error.message.includes("revenuecat_identity_mapping_ambiguous")
        ) {
          return publicErrorResponse(
            request,
            409,
            "ambiguous_customer_mapping",
            "Ambiguous customer mapping.",
          );
        }
        if (databaseErrorIsRetryable(error.code)) {
          return publicErrorResponse(
            request,
            503,
            "database_unavailable",
            "Database temporarily unavailable.",
            { retryAfterSeconds: 30 },
          );
        }
      } else {
        logIdentitySafeError("revenuecat_webhook_failed", {
          stage: "processing",
          code: "unexpected_failure",
        });
      }

      return publicErrorResponse(
        request,
        500,
        "internal_error",
        "Webhook processing failed.",
      );
    }
  };
}
