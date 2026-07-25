import { SupabaseClient } from "@supabase/supabase-js";
import { jsonResponse } from "../_shared/edgeHandler.ts";
import {
  isJsonMediaType,
  publicErrorResponse,
  readRequestBodyWithinLimit,
  requestIdFor,
  timingSafeCompare,
} from "../_shared/http.ts";
import {
  applyRevenueCatCustomerState,
  getRevenueCatWebhookEventResult,
  RevenueCatDatabaseError,
  scheduleRevenueCatReconciliation,
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
  deriveRevenueCatEntitlementState,
  fetchRevenueCatCustomerInfo,
  RevenueCatApiError,
} from "./subscriber.ts";

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
      console.error(
        `[revenuecat-webhook] request_id=${requestId} required secrets are unavailable.`,
      );
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
    } catch (error) {
      console.error(
        `[revenuecat-webhook] request_id=${requestId} signature verification unavailable:`,
        error,
      );
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
        await scheduleRevenueCatReconciliation(
          subjects,
          dependencies.supabaseAdmin,
        );
        console.info(
          `[revenuecat-webhook] duplicate event ${event.id}; ${existingResult.subjectCount} subject(s).`,
        );
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

      // RevenueCat recommends fetching CustomerInfo after each webhook. The
      // event itself is a synchronization signal, never the entitlement truth.
      // A committed duplicate and an event with no Merian UUID are the only
      // safe provider-lookup bypasses. TRANSFER reconciles both sides before
      // one database transaction so it can never half-move access.
      const stateSubjects = await Promise.all(subjects.map(async (subject) => {
        const customerInfo = await fetchRevenueCatCustomerInfo(
          subject.lookupAppUserId,
          dependencies.config.apiKey,
          fetchImpl,
        );
        if (
          customerInfo.requestDateMs >
            now() + REVENUECAT_SIGNATURE_TOLERANCE_SECONDS * 1_000
        ) {
          throw new RevenueCatApiError(
            "RevenueCat CustomerInfo snapshot timestamp is in the future.",
            true,
          );
        }
        const entitlement = deriveRevenueCatEntitlementState(
          customerInfo,
          event,
        );
        return {
          kind: subject.kind,
          lookupAppUserId: subject.lookupAppUserId,
          candidateUserIds: subject.candidateUserIds,
          authoritativeSnapshotAtMs: customerInfo.requestDateMs,
          targetTier: entitlement.targetTier,
          targetExpiresAt: entitlement.expiresAt,
        };
      }));

      const result = await applyRevenueCatCustomerState(
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
      await scheduleRevenueCatReconciliation(
        subjects,
        dependencies.supabaseAdmin,
      );

      console.info(
        `[revenuecat-webhook] ${result.outcome} event ${event.id}; ${result.appliedCount} applied, ${result.staleCount} stale.`,
      );
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
        console.error(
          `[revenuecat-webhook] request_id=${requestId} ${error.message}`,
        );
        return publicErrorResponse(
          request,
          error.retryable ? 503 : 502,
          "entitlement_lookup_failed",
          "Authoritative entitlement lookup failed.",
          { retryAfterSeconds: error.retryable ? 30 : undefined },
        );
      }

      if (error instanceof RevenueCatDatabaseError) {
        console.error(
          `[revenuecat-webhook] request_id=${requestId} database transition failed (${
            error.code ?? "unknown"
          }): ${error.message}`,
        );
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
        if (error.message.includes("revenuecat_user_mapping_ambiguous")) {
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
        console.error(
          `[revenuecat-webhook] request_id=${requestId} unexpected failure:`,
          error,
        );
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
