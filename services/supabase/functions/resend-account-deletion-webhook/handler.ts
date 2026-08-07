import type { SupabaseClient } from "@supabase/supabase-js";
import { jsonResponse } from "../_shared/edgeHandler.ts";
import {
  isJsonMediaType,
  publicErrorResponse,
  readRequestBodyWithinLimit,
  requestIdFor,
} from "../_shared/http.ts";
import {
  recordResendAccountDeletionEvent,
  ResendAccountDeletionDatabaseError,
  type ResendAccountDeletionEventOutcome,
} from "./db.ts";
import {
  MAX_RESEND_WEBHOOK_BYTES,
  parseResendAccountDeletionEvent,
  ResendPayloadError,
} from "./protocol.ts";
import {
  isValidResendSigningSecret,
  verifyResendSignature,
} from "./signature.ts";

export interface ResendAccountDeletionWebhookDependencies {
  supabaseAdmin: SupabaseClient;
  signingSecret: string;
  now?: () => number;
  recordEvent?: typeof recordResendAccountDeletionEvent;
}

function configurationIsComplete(signingSecret: string): boolean {
  return isValidResendSigningSecret(signingSecret) &&
    signingSecret.length >= 24 &&
    signingSecret.length <= 512 &&
    !containsAsciiControlCharacter(signingSecret);
}

function databaseErrorIsRetryable(code: string | null): boolean {
  return code === null ||
    code.startsWith("08") ||
    ["40001", "40P01", "53300", "57014", "57P01", "P0001"].includes(code);
}

export function createResendAccountDeletionWebhookHandler(
  dependencies: ResendAccountDeletionWebhookDependencies,
): (request: Request) => Promise<Response> {
  const now = dependencies.now ?? Date.now;
  const recordEvent = dependencies.recordEvent ??
    recordResendAccountDeletionEvent;

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
    if (!configurationIsComplete(dependencies.signingSecret)) {
      console.error(
        `[resend-account-deletion-webhook] request_id=${requestId} signing secret is unavailable.`,
      );
      return publicErrorResponse(
        request,
        503,
        "service_unavailable",
        "The service is temporarily unavailable.",
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
      MAX_RESEND_WEBHOOK_BYTES,
    );
    if (bodyResult.error || !bodyResult.bytes) {
      const error = bodyResult.error ?? {
        status: 400 as const,
        code: "invalid_json" as const,
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
      verifiedSignature = await verifyResendSignature(
        {
          id: request.headers.get("svix-id"),
          timestamp: request.headers.get("svix-timestamp"),
          signature: request.headers.get("svix-signature"),
        },
        dependencies.signingSecret,
        rawBytes,
        now(),
      );
    } catch {
      console.error(
        `[resend-account-deletion-webhook] request_id=${requestId} signature verification unavailable.`,
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
        throw new ResendPayloadError("Invalid UTF-8 JSON.");
      }
      const event = parseResendAccountDeletionEvent(rawBody);
      if (!event.relevant) {
        return successResponse(requestId, "ignored");
      }

      const outcome = await recordEvent(
        event,
        verifiedSignature.messageId,
        dependencies.supabaseAdmin,
      );
      return successResponse(requestId, outcome);
    } catch (error) {
      if (error instanceof ResendPayloadError) {
        return publicErrorResponse(
          request,
          400,
          "invalid_webhook_payload",
          "Invalid webhook payload.",
        );
      }
      if (error instanceof ResendAccountDeletionDatabaseError) {
        console.error(
          `[resend-account-deletion-webhook] request_id=${requestId} database transition failed (${
            error.code ?? "unknown"
          }).`,
        );
        if (
          error.message.includes("manual_revocation_event_id_conflict") ||
          error.message.includes("manual_revocation_delivery_id_conflict")
        ) {
          return publicErrorResponse(
            request,
            409,
            "event_identifier_conflict",
            "Webhook event conflicted with durable state.",
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

function successResponse(
  requestId: string,
  outcome: ResendAccountDeletionEventOutcome | "ignored",
): Response {
  return jsonResponse(
    { success: true, outcome },
    200,
    { "Cache-Control": "private, no-store", "X-Request-ID": requestId },
  );
}

function containsAsciiControlCharacter(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code <= 0x1F || code === 0x7F) return true;
  }
  return false;
}
