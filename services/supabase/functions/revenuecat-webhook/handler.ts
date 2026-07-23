import { SupabaseClient } from "@supabase/supabase-js";
import { jsonResponse } from "../_shared/edgeHandler.ts";
import { timingSafeCompare } from "../_shared/http.ts";
import {
  applyRevenueCatCustomerState,
  getRevenueCatWebhookEventResult,
  RevenueCatDatabaseError,
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

class RevenueCatBodyTooLargeError extends Error {}

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

async function readBoundedBody(
  request: Request,
  maximumBytes: number,
): Promise<Uint8Array> {
  if (!request.body) return new Uint8Array();

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > maximumBytes) {
        await reader.cancel("request body exceeded limit");
        throw new RevenueCatBodyTooLargeError();
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const body = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return body;
}

export function createRevenueCatWebhookHandler(
  dependencies: RevenueCatWebhookDependencies,
): (request: Request) => Promise<Response> {
  const fetchImpl = dependencies.fetchImpl ?? fetch;
  const now = dependencies.now ?? Date.now;

  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return jsonResponse(
        { error: "Method not allowed." },
        405,
        { Allow: "POST" },
      );
    }

    if (!configurationIsComplete(dependencies.config)) {
      console.error(
        "[revenuecat-webhook] Required RevenueCat secrets are unavailable.",
      );
      return jsonResponse({ error: "Service unavailable." }, 503);
    }

    const authorization = request.headers.get("Authorization") ?? "";
    if (
      !timingSafeCompare(
        authorization,
        `Bearer ${dependencies.config.authorizationSecret}`,
      )
    ) {
      return jsonResponse({ error: "Unauthorized." }, 401);
    }

    const contentLength = Number(request.headers.get("Content-Length"));
    if (
      Number.isFinite(contentLength) &&
      contentLength > MAX_REVENUECAT_WEBHOOK_BYTES
    ) {
      return jsonResponse({ error: "Request body too large." }, 413);
    }

    let rawBytes: Uint8Array;
    try {
      rawBytes = await readBoundedBody(
        request,
        MAX_REVENUECAT_WEBHOOK_BYTES,
      );
    } catch (error) {
      if (error instanceof RevenueCatBodyTooLargeError) {
        return jsonResponse({ error: "Request body too large." }, 413);
      }
      return jsonResponse({ error: "Invalid request body." }, 400);
    }

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
        "[revenuecat-webhook] Signature verification unavailable:",
        error,
      );
      return jsonResponse({ error: "Service unavailable." }, 503);
    }
    if (!verifiedSignature) {
      return jsonResponse({ error: "Unauthorized." }, 401);
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
        console.info(
          `[revenuecat-webhook] duplicate event ${event.id}; ${existingResult.subjectCount} subject(s).`,
        );
        return jsonResponse({
          success: true,
          outcome: "duplicate",
          subject_count: existingResult.subjectCount,
          applied_count: existingResult.appliedCount,
          stale_count: existingResult.staleCount,
        });
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

      console.info(
        `[revenuecat-webhook] ${result.outcome} event ${event.id}; ${result.appliedCount} applied, ${result.staleCount} stale.`,
      );
      return jsonResponse({
        success: true,
        outcome: result.outcome,
        subject_count: result.subjectCount,
        applied_count: result.appliedCount,
        stale_count: result.staleCount,
      });
    } catch (error) {
      if (error instanceof RevenueCatPayloadError) {
        return jsonResponse({ error: "Invalid webhook payload." }, 400);
      }

      if (error instanceof RevenueCatApiError) {
        console.error(`[revenuecat-webhook] ${error.message}`);
        return jsonResponse(
          { error: "Authoritative entitlement lookup failed." },
          error.retryable ? 503 : 502,
          error.retryable ? { "Retry-After": "30" } : {},
        );
      }

      if (error instanceof RevenueCatDatabaseError) {
        console.error(
          `[revenuecat-webhook] Database transition failed (${
            error.code ?? "unknown"
          }): ${error.message}`,
        );
        if (error.message.includes("revenuecat_user_not_found")) {
          return jsonResponse(
            { error: "User profile is not ready." },
            503,
            { "Retry-After": "30" },
          );
        }
        if (error.message.includes("revenuecat_event_id_conflict")) {
          return jsonResponse({ error: "Event identifier conflict." }, 409);
        }
        if (error.message.includes("revenuecat_user_mapping_ambiguous")) {
          return jsonResponse({ error: "Ambiguous customer mapping." }, 409);
        }
        if (databaseErrorIsRetryable(error.code)) {
          return jsonResponse(
            { error: "Database temporarily unavailable." },
            503,
            { "Retry-After": "30" },
          );
        }
      } else {
        console.error("[revenuecat-webhook] Unexpected failure:", error);
      }

      return jsonResponse({ error: "Webhook processing failed." }, 500);
    }
  };
}
