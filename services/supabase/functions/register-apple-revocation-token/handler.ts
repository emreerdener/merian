import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type AppleAuthorizationExchange,
  AppleAuthorizationExchangeError,
  type AppleRevocationResult,
  exchangeAppleAuthorizationCode,
  revokeAppleRefreshToken,
} from "../_shared/appleSignIn.ts";
import { jsonResponse, logStructuredError } from "../_shared/edgeHandler.ts";
import { parseJsonBody, PublicHttpError } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import {
  appleRevocationRegistrationExists,
  storeAppleRevocationCredential,
} from "./db.ts";

export interface AppleCredentialRegistrationDependencies {
  registrationExists?: (
    supabaseAdmin: SupabaseClient,
    userId: string,
    registrationId: string,
  ) => Promise<boolean>;
  exchange?: (
    authorizationCode: string,
    identityToken: string,
  ) => Promise<AppleAuthorizationExchange>;
  store?: (
    supabaseAdmin: SupabaseClient,
    input: {
      userId: string;
      registrationId: string;
      appleSubject: string;
      refreshToken: string;
    },
  ) => Promise<void>;
  compensate?: (refreshToken: string) => Promise<AppleRevocationResult>;
}

export async function handleAppleCredentialRegistration(
  req: Request,
  userId: string,
  supabaseAdmin: SupabaseClient,
  dependencies: AppleCredentialRegistrationDependencies = {},
): Promise<Response> {
  const parsedBody = await parseJsonBody(req, { limit: "small" });
  if (parsedBody instanceof Response) return parsedBody;

  const registrationId = requireUuid(
    parsedBody.registration_id,
    "registration_id",
  );
  const authorizationCode = safeCredential(
    parsedBody.authorization_code,
    "authorization_code",
    1,
    8_192,
  );
  const identityToken = safeCredential(
    parsedBody.identity_token,
    "identity_token",
    32,
    16_384,
  );
  const registrationExists = dependencies.registrationExists ??
    appleRevocationRegistrationExists;

  try {
    if (
      await registrationExists(
        supabaseAdmin,
        userId,
        registrationId,
      )
    ) {
      return registeredResponse();
    }
  } catch {
    throw new PublicHttpError(
      503,
      "apple_registration_lookup_unavailable",
      "Sign in with Apple could not be secured. Please try again.",
      1,
    );
  }

  const exchange = dependencies.exchange ?? exchangeAppleAuthorizationCode;
  let credential: AppleAuthorizationExchange;
  try {
    credential = await exchange(authorizationCode, identityToken);
  } catch (error) {
    if (error instanceof AppleAuthorizationExchangeError) {
      logStructuredError("apple_credential_exchange_failed", {
        code: error.code,
        retryable: error.retryable,
      });
      throw new PublicHttpError(
        error.retryable ? 503 : 409,
        error.retryable
          ? "apple_credential_exchange_unavailable"
          : "apple_authorization_expired",
        error.retryable
          ? "Sign in with Apple could not be secured. Please try again."
          : "Apple authorization expired. Please start Sign in with Apple again.",
        error.retryable ? 1 : undefined,
      );
    }
    throw new PublicHttpError(
      503,
      "apple_credential_exchange_unavailable",
      "Sign in with Apple could not be secured. Please try again.",
      1,
    );
  }

  const store = dependencies.store ?? storeAppleRevocationCredential;
  try {
    await store(supabaseAdmin, {
      userId,
      registrationId,
      appleSubject: credential.subject,
      refreshToken: credential.refreshToken,
    });
  } catch {
    // A database transaction can commit even when its HTTP response is lost.
    // Reconcile the token-free receipt before compensating so an already
    // durable credential is not revoked merely because delivery was
    // ambiguous.
    try {
      if (
        await registrationExists(
          supabaseAdmin,
          userId,
          registrationId,
        )
      ) {
        return registeredResponse();
      }
    } catch {
      // The outcome remains ambiguous. Revocation is the fail-closed choice:
      // it prevents an untracked Apple authorization from surviving.
    }

    // The authorization code cannot be reused after a successful exchange. If
    // the receipt proves the database did not commit (or cannot be read),
    // revoke the newly issued refresh token so the failure cannot create an
    // untracked Apple authorization.
    const compensate = dependencies.compensate ?? revokeAppleRefreshToken;
    const compensation = await compensate(credential.refreshToken);
    logStructuredError("apple_credential_persistence_failed", {
      compensation_succeeded: compensation.succeeded,
      compensation_code: compensation.errorCode ?? null,
    });
    throw new PublicHttpError(
      503,
      compensation.succeeded
        ? "apple_credential_capture_failed"
        : "apple_credential_compensation_failed",
      "Sign in with Apple could not be secured. Please start sign-in again.",
      1,
    );
  }

  return registeredResponse();
}

function safeCredential(
  value: unknown,
  fieldName: string,
  minimumLength: number,
  maximumLength: number,
): string {
  if (
    typeof value !== "string" ||
    value.length < minimumLength ||
    value.length > maximumLength ||
    containsAsciiControlCharacter(value)
  ) {
    throw new PublicHttpError(
      400,
      "invalid_apple_authorization_payload",
      `${fieldName} is invalid.`,
    );
  }
  return value;
}

function containsAsciiControlCharacter(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code <= 0x1F || code === 0x7F) {
      return true;
    }
  }
  return false;
}

function registeredResponse(): Response {
  return jsonResponse(
    { success: true, status: "registered" },
    200,
    { "Cache-Control": "private, no-store" },
  );
}
