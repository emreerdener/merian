import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from "jose";
import {
  fetchWithDeadline,
  OutboundRequestTimeoutError,
  readResponseJsonWithinLimit,
  readResponseTextWithinLimit,
} from "./outbound.ts";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_TOKEN_URL = `${APPLE_ISSUER}/auth/token`;
const APPLE_REVOCATION_URL = `${APPLE_ISSUER}/auth/revoke`;
const APPLE_CLIENT_ID = "app.merian.Merian";
const APPLE_REQUEST_TIMEOUT_MS = 10_000;
const APPLE_RESPONSE_LIMIT_BYTES = 16 * 1024;
const APPLE_CLIENT_SECRET_LIFETIME_SECONDS = 5 * 60;

const appleJwks = createRemoteJWKSet(
  new URL(`${APPLE_ISSUER}/auth/keys`),
  { timeoutDuration: 5_000, cooldownDuration: 30_000 },
);

export interface AppleSignInConfiguration {
  clientId: string;
  teamId: string;
  keyId: string;
  privateKey: string;
}

export interface AppleAuthorizationExchange {
  subject: string;
  refreshToken: string;
}

export interface AppleRevocationResult {
  succeeded: boolean;
  errorCode?: string;
}

export interface AppleSignInDependencies {
  fetcher?: typeof fetch;
  configuration?: AppleSignInConfiguration;
  clientSecret?: (
    configuration: AppleSignInConfiguration,
  ) => Promise<string>;
  verifyIdentityToken?: (
    identityToken: string,
    clientId: string,
  ) => Promise<string>;
}

export class AppleAuthorizationExchangeError extends Error {
  readonly code: string;
  readonly retryable: boolean;

  constructor(code: string, retryable: boolean) {
    super("The Apple authorization credential could not be secured.");
    this.name = "AppleAuthorizationExchangeError";
    this.code = code;
    this.retryable = retryable;
  }
}

export function appleSignInConfigurationFromEnvironment(): AppleSignInConfiguration {
  const teamId = Deno.env.get("APPLE_SIGN_IN_TEAM_ID")?.trim() ?? "";
  const keyId = Deno.env.get("APPLE_SIGN_IN_KEY_ID")?.trim() ?? "";
  const privateKey = normalizePrivateKey(
    Deno.env.get("APPLE_SIGN_IN_PRIVATE_KEY") ?? "",
  );

  if (
    !isSafeIdentifier(teamId, 32) ||
    !isSafeIdentifier(keyId, 64) ||
    !privateKey.startsWith("-----BEGIN PRIVATE KEY-----") ||
    !privateKey.endsWith("-----END PRIVATE KEY-----")
  ) {
    throw new AppleAuthorizationExchangeError(
      "apple_configuration_missing",
      true,
    );
  }

  return {
    clientId: APPLE_CLIENT_ID,
    teamId,
    keyId,
    privateKey,
  };
}

export async function createAppleClientSecret(
  configuration: AppleSignInConfiguration,
  now: Date = new Date(),
): Promise<string> {
  try {
    const key = await importPKCS8(configuration.privateKey, "ES256");
    const issuedAt = Math.floor(now.getTime() / 1000);
    return await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: configuration.keyId })
      .setIssuer(configuration.teamId)
      .setSubject(configuration.clientId)
      .setAudience(APPLE_ISSUER)
      .setIssuedAt(issuedAt)
      .setExpirationTime(
        issuedAt + APPLE_CLIENT_SECRET_LIFETIME_SECONDS,
      )
      .sign(key);
  } catch {
    throw new AppleAuthorizationExchangeError(
      "apple_client_secret_invalid",
      true,
    );
  }
}

export async function verifyAppleIdentityToken(
  identityToken: string,
  clientId: string,
): Promise<string> {
  try {
    const { payload } = await jwtVerify(identityToken, appleJwks, {
      issuer: APPLE_ISSUER,
      audience: clientId,
      algorithms: ["RS256"],
    });
    const subject = typeof payload.sub === "string" ? payload.sub : "";
    if (!isSafeAppleSubject(subject)) throw new Error("invalid subject");
    return subject;
  } catch {
    throw new AppleAuthorizationExchangeError(
      "apple_identity_token_invalid",
      false,
    );
  }
}

export async function exchangeAppleAuthorizationCode(
  authorizationCode: string,
  presentedIdentityToken: string,
  dependencies: AppleSignInDependencies = {},
): Promise<AppleAuthorizationExchange> {
  if (
    !isSafeOpaqueCredential(authorizationCode, 1, 8_192) ||
    !isSafeOpaqueCredential(presentedIdentityToken, 32, 16_384)
  ) {
    throw new AppleAuthorizationExchangeError(
      "apple_authorization_payload_invalid",
      false,
    );
  }

  const configuration = dependencies.configuration ??
    appleSignInConfigurationFromEnvironment();
  const verify = dependencies.verifyIdentityToken ?? verifyAppleIdentityToken;
  const presentedSubject = await verify(
    presentedIdentityToken,
    configuration.clientId,
  );
  const makeClientSecret = dependencies.clientSecret ?? createAppleClientSecret;
  const clientSecret = await makeClientSecret(configuration);

  let response: Response;
  try {
    response = await fetchWithDeadline(
      APPLE_TOKEN_URL,
      {
        method: "POST",
        headers: {
          "content-type": "application/x-www-form-urlencoded",
          "accept": "application/json",
        },
        body: new URLSearchParams({
          client_id: configuration.clientId,
          client_secret: clientSecret,
          code: authorizationCode,
          grant_type: "authorization_code",
        }),
      },
      {
        fetcher: dependencies.fetcher,
        timeoutMs: APPLE_REQUEST_TIMEOUT_MS,
      },
    );
  } catch (error) {
    throw new AppleAuthorizationExchangeError(
      error instanceof OutboundRequestTimeoutError
        ? "apple_token_exchange_timeout"
        : "apple_token_exchange_unavailable",
      true,
    );
  }

  if (!response.ok) {
    const providerCode = await safeAppleErrorCode(response);
    throw new AppleAuthorizationExchangeError(
      `apple_token_exchange_${providerCode}`,
      providerCode !== "invalid_grant" &&
        providerCode !== "invalid_request",
    );
  }

  let body: unknown;
  try {
    body = await readResponseJsonWithinLimit(
      response,
      APPLE_RESPONSE_LIMIT_BYTES,
    );
  } catch {
    throw new AppleAuthorizationExchangeError(
      "apple_token_exchange_invalid_response",
      true,
    );
  }

  if (!isAppleTokenResponse(body)) {
    throw new AppleAuthorizationExchangeError(
      "apple_token_exchange_invalid_response",
      true,
    );
  }

  const exchangedSubject = await verify(body.id_token, configuration.clientId);
  if (exchangedSubject !== presentedSubject) {
    throw new AppleAuthorizationExchangeError(
      "apple_token_subject_mismatch",
      false,
    );
  }

  return {
    subject: exchangedSubject,
    refreshToken: body.refresh_token,
  };
}

export async function revokeAppleRefreshToken(
  refreshToken: string,
  dependencies: AppleSignInDependencies = {},
): Promise<AppleRevocationResult> {
  if (!isSafeOpaqueCredential(refreshToken, 16, 8_192)) {
    return { succeeded: false, errorCode: "apple_refresh_token_invalid" };
  }

  let configuration: AppleSignInConfiguration;
  let clientSecret: string;
  try {
    configuration = dependencies.configuration ??
      appleSignInConfigurationFromEnvironment();
    const makeClientSecret = dependencies.clientSecret ??
      createAppleClientSecret;
    clientSecret = await makeClientSecret(configuration);
  } catch (error) {
    return {
      succeeded: false,
      errorCode: error instanceof AppleAuthorizationExchangeError
        ? error.code
        : "apple_client_secret_invalid",
    };
  }

  let response: Response;
  try {
    response = await fetchWithDeadline(
      APPLE_REVOCATION_URL,
      {
        method: "POST",
        headers: {
          "content-type": "application/x-www-form-urlencoded",
          "accept": "application/json",
        },
        body: new URLSearchParams({
          client_id: configuration.clientId,
          client_secret: clientSecret,
          token: refreshToken,
          token_type_hint: "refresh_token",
        }),
      },
      {
        fetcher: dependencies.fetcher,
        timeoutMs: APPLE_REQUEST_TIMEOUT_MS,
      },
    );
  } catch (error) {
    return {
      succeeded: false,
      errorCode: error instanceof OutboundRequestTimeoutError
        ? "apple_revoke_timeout"
        : "apple_revoke_unavailable",
    };
  }

  if (response.status === 200) {
    await response.body?.cancel().catch(() => undefined);
    return { succeeded: true };
  }

  return {
    succeeded: false,
    errorCode: `apple_revoke_${await safeAppleErrorCode(response)}`,
  };
}

function normalizePrivateKey(rawValue: string): string {
  return rawValue.replaceAll("\\n", "\n").trim();
}

function isSafeIdentifier(value: string, maximumLength: number): boolean {
  return value.length >= 1 && value.length <= maximumLength &&
    /^[A-Za-z0-9._-]+$/.test(value);
}

function isSafeAppleSubject(subject: string): boolean {
  return subject.length >= 1 && subject.length <= 255 &&
    !containsAsciiControlCharacter(subject);
}

function isSafeOpaqueCredential(
  value: string,
  minimumLength: number,
  maximumLength: number,
): boolean {
  return value.length >= minimumLength && value.length <= maximumLength &&
    !containsAsciiControlCharacter(value);
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

function isAppleTokenResponse(value: unknown): value is {
  refresh_token: string;
  id_token: string;
} {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const body = value as Record<string, unknown>;
  return typeof body.refresh_token === "string" &&
    isSafeOpaqueCredential(body.refresh_token, 16, 8_192) &&
    typeof body.id_token === "string" &&
    isSafeOpaqueCredential(body.id_token, 32, 16_384);
}

async function safeAppleErrorCode(response: Response): Promise<string> {
  let code = `http_${response.status}`;
  try {
    const text = await readResponseTextWithinLimit(
      response,
      APPLE_RESPONSE_LIMIT_BYTES,
    );
    const body = JSON.parse(text) as { error?: unknown };
    if (
      typeof body.error === "string" &&
      [
        "invalid_request",
        "invalid_client",
        "invalid_grant",
        "unauthorized_client",
        "unsupported_grant_type",
        "invalid_scope",
      ].includes(body.error)
    ) {
      code = body.error;
    }
  } catch {
    // Preserve the bounded status-only diagnostic for malformed responses.
  }
  return code;
}
