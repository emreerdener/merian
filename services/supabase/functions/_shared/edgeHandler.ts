import { SupabaseClient, User } from "@supabase/supabase-js";
import { requireAuth } from "./auth.ts";
import {
  corsHeaders,
  defaultPublicErrorCode,
  isExplicitPublicErrorResponse,
  jsonResponse,
  MERIAN_HANDLER_RESPONSE_HEADER,
  publicErrorResponse,
  PublicHttpError,
  requestIdFor,
} from "./http.ts";
import { requireServerApiKeyFromEnvironment } from "./serviceRoleAuth.ts";
import { createServiceRoleClient } from "./serviceRoleClient.ts";

export { jsonResponse };

export type EdgeAuthenticator = (
  req: Request,
  supabaseAdmin: SupabaseClient,
) => Promise<{ user: User | null; response: Response | null }>;

export type PublicEdgeHandler = (
  req: Request,
) => Response | Promise<Response>;

/**
 * Emits a structured JSON error log for alertable operational events.
 * Use this (not bare console.error) for any failure that requires human
 * attention — partial deletes, inconsistent state, IDOR attempts, etc.
 * The consistent shape makes log-aggregation queries deterministic.
 */
export function logStructuredError(
  event: string,
  details: Record<string, unknown>,
): void {
  console.error(JSON.stringify({
    ...details,
    event,
    ts: new Date().toISOString(),
  }));
}

export interface IdentitySafeErrorDetails {
  identityKind?: string;
  operation?: string;
  stage?: string;
  code?: string;
  status?: number;
}

const IDENTITY_SAFE_LOG_TOKEN = /^[a-z][a-z0-9_]{0,63}$/;
const UUID_LIKE_LOG_TOKEN =
  /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
const IDENTITY_SAFE_CODE_SOURCE = /^[A-Za-z][A-Za-z0-9_]{0,63}$/;

function identitySafeLogToken(value: string, fallback: string): string {
  if (UUID_LIKE_LOG_TOKEN.test(value)) return fallback;
  const normalized = value.trim().toLowerCase().replaceAll(
    /[^a-z0-9_]/g,
    "_",
  ).slice(0, 64);
  if (
    normalized.split("_").some((segment) => segment.length >= 16)
  ) {
    return fallback;
  }
  return IDENTITY_SAFE_LOG_TOKEN.test(normalized) ? normalized : fallback;
}

function identitySafeCodeToken(value: string): string {
  // Codes are machine-authored names, never prose. Rejecting separators that
  // occur in messages, URLs, and provider customer IDs prevents a future
  // caller from laundering raw identity/error text through normalization.
  const trimmed = value.trim();
  if (!IDENTITY_SAFE_CODE_SOURCE.test(trimmed)) return "operation_failed";
  return identitySafeLogToken(trimmed, "operation_failed");
}

/**
 * Emits an allowlisted operational error without accepting arbitrary detail
 * objects, Error instances, provider bodies, or identity-bearing values.
 * Authentication and purchase-identity paths use this narrower boundary so a
 * customer UUID, principal ID, handoff ID, or raw database/provider message
 * cannot accidentally enter logs.
 */
export function logIdentitySafeError(
  event: string,
  details: IdentitySafeErrorDetails = {},
): void {
  const safeDetails: Record<string, string | number> = {};
  if (details.identityKind !== undefined) {
    safeDetails.identity_kind = identitySafeLogToken(
      details.identityKind,
      "unknown",
    );
  }
  if (details.operation !== undefined) {
    safeDetails.operation = identitySafeLogToken(
      details.operation,
      "unknown",
    );
  }
  if (details.stage !== undefined) {
    safeDetails.stage = identitySafeLogToken(details.stage, "unknown");
  }
  if (details.code !== undefined) {
    safeDetails.code = identitySafeCodeToken(details.code);
  }
  if (
    details.status !== undefined && Number.isInteger(details.status) &&
    details.status >= 100 && details.status <= 599
  ) {
    safeDetails.status = details.status;
  }

  logStructuredError(
    identitySafeLogToken(event, "identity_operation_failed"),
    safeDetails,
  );
}

/**
 * Schedules a background task using EdgeRuntime.waitUntil when available,
 * falling back gracefully for local development.
 */
export function runBackground(task: Promise<void>): void {
  const globalObj = globalThis as unknown as {
    EdgeRuntime?: { waitUntil: (p: Promise<void>) => void };
  };
  if (
    typeof globalObj.EdgeRuntime === "object" &&
    typeof globalObj.EdgeRuntime.waitUntil === "function"
  ) {
    globalObj.EdgeRuntime.waitUntil(task);
  } else {
    task.catch((error: unknown) => {
      logIdentitySafeError("background_task_failed", {
        code: identitySafeErrorKind(error),
      });
    });
  }
}

/**
 * Universal Deno edge function wrapper handling CORS preflights,
 * JWT authentication, and top-level error handling.
 */
export async function withEdgeHandler(
  req: Request,
  handler: (
    user: User,
    supabaseAdmin: SupabaseClient,
    context: { authDurationMs: number },
  ) => Promise<Response>,
  options: { authenticate?: EdgeAuthenticator } = {},
): Promise<Response> {
  const requestId = requestIdFor(req);

  if (req.method === "OPTIONS") {
    return withRequestMetadata(
      new Response("ok", { headers: corsHeaders }),
      requestId,
    );
  }

  try {
    const supabaseAdmin = createServiceRoleClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      requireServerApiKeyFromEnvironment(),
    );

    const authStart = performance.now();
    const authenticate = options.authenticate ?? requireAuth;
    const { user, response } = await authenticate(req, supabaseAdmin);
    const authDuration = performance.now() - authStart;

    if (response || !user) {
      return await finalizeEdgeResponse(
        req,
        response || jsonResponse({ error: "Unauthorized" }, 401),
        authDuration,
      );
    }

    return await finalizeEdgeResponse(
      req,
      await handler(user, supabaseAdmin, { authDurationMs: authDuration }),
      authDuration,
    );
  } catch (error: unknown) {
    return boundaryFailureResponse(req, error);
  }
}

/**
 * Applies the same request-ID and public-error boundary to deliberately public,
 * webhook, and service-authenticated handlers that own authentication outside
 * `withEdgeHandler`.
 */
export async function withPublicEdgeHandler(
  req: Request,
  handler: PublicEdgeHandler,
): Promise<Response> {
  const requestId = requestIdFor(req);
  try {
    const response = await handler(req);
    return await finalizePublicResponse(
      req,
      withRequestMetadata(response, requestId),
      isExplicitPublicErrorResponse(response),
    );
  } catch (error: unknown) {
    return boundaryFailureResponse(req, error);
  }
}

/**
 * Registers a custom-auth/public handler without allowing it to bypass the
 * fleet-wide response boundary.
 */
export function serveEdge(handler: PublicEdgeHandler): void {
  Deno.serve((req: Request) => withPublicEdgeHandler(req, handler));
}

async function finalizeEdgeResponse(
  req: Request,
  response: Response,
  durationMs: number,
): Promise<Response> {
  const requestId = requestIdFor(req);
  const responseWithTiming = withAuthServerTiming(
    response,
    durationMs,
    requestId,
  );
  return await finalizePublicResponse(
    req,
    responseWithTiming,
    isExplicitPublicErrorResponse(response),
  );
}

async function finalizePublicResponse(
  req: Request,
  response: Response,
  explicitPublicError = false,
): Promise<Response> {
  const requestId = requestIdFor(req);
  if (explicitPublicError) return response;
  if (response.status < 400) return response;

  if (response.status >= 500) {
    const retryAfterSeconds = retryAfterFromResponse(response);
    return publicErrorResponse(
      req,
      response.status,
      defaultPublicErrorCode(response.status),
      response.status === 503
        ? "The service is temporarily unavailable."
        : "The request could not be completed.",
      {
        extraHeaders: safePublicErrorHeaders(response),
        retryAfterSeconds,
      },
    );
  }

  const contentType = response.headers.get("content-type") ?? "";
  let payload: Record<string, unknown> = {};
  if (contentType.toLowerCase().includes("application/json")) {
    try {
      const parsed = await response.clone().json();
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        payload = parsed as Record<string, unknown>;
      }
    } catch {
      // Fall through to the stable generic 4xx envelope.
    }
  }

  const existingCode = typeof payload.code === "string" &&
      /^[a-z][a-z0-9_]{1,63}$/.test(payload.code)
    ? payload.code
    : defaultPublicErrorCode(response.status);
  const existingMessage = typeof payload.error === "string" &&
      payload.error.trim().length > 0 &&
      payload.error.length <= 500
    ? payload.error
    : "The request is invalid.";

  return jsonResponse(
    {
      ...payload,
      error: existingMessage,
      code: existingCode,
      request_id: requestId,
    },
    response.status,
    {
      ...safePublicErrorHeaders(response),
      "Cache-Control": "private, no-store",
      "Content-Type": "application/json",
      "X-Request-ID": requestId,
    },
  );
}

function boundaryFailureResponse(req: Request, error: unknown): Response {
  const requestId = requestIdFor(req);
  logStructuredError("edge_function_request_failed", {
    request_id: requestId,
    method: identitySafeLogToken(req.method, "unknown"),
    error_kind: identitySafeErrorKind(error),
  });

  if (error instanceof PublicHttpError) {
    return publicErrorResponse(
      req,
      error.status,
      error.code,
      error.message,
      { retryAfterSeconds: validRetryAfter(error.retryAfterSeconds) },
    );
  }

  return publicErrorResponse(
    req,
    500,
    "internal_error",
    "The request could not be completed.",
  );
}

function identitySafeErrorKind(error: unknown): string {
  return identitySafeLogToken(
    error instanceof Error ? error.name : typeof error,
    "operation_failed",
  );
}

function withAuthServerTiming(
  response: Response,
  durationMs: number,
  requestId: string,
): Response {
  const headers = new Headers(response.headers);
  const existing = headers.get("Server-Timing");
  const authMetric = `auth;dur=${Math.max(durationMs, 0).toFixed(1)}`;
  headers.set(
    "Server-Timing",
    existing ? `${authMetric}, ${existing}` : authMetric,
  );
  headers.set("X-Request-ID", requestId);
  headers.set(
    "X-Merian-Handler",
    MERIAN_HANDLER_RESPONSE_HEADER["X-Merian-Handler"],
  );
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function withRequestMetadata(response: Response, requestId: string): Response {
  const headers = new Headers(response.headers);
  headers.set("X-Request-ID", requestId);
  headers.set(
    "X-Merian-Handler",
    MERIAN_HANDLER_RESPONSE_HEADER["X-Merian-Handler"],
  );
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function safePublicErrorHeaders(response: Response): Record<string, string> {
  const headers: Record<string, string> = {};
  for (
    const name of [
      "Allow",
      "Server-Timing",
      "WWW-Authenticate",
      "X-Merian-Handler",
    ]
  ) {
    const value = response.headers.get(name);
    if (value) headers[name] = value;
  }
  return headers;
}

function retryAfterFromResponse(response: Response): number | undefined {
  const value = response.headers.get("Retry-After")?.trim() ?? "";
  return /^[1-9][0-9]{0,4}$/.test(value)
    ? validRetryAfter(Number(value))
    : undefined;
}

function validRetryAfter(value: number | undefined): number | undefined {
  return typeof value === "number" &&
      Number.isInteger(value) &&
      value > 0 &&
      value <= 86_400
    ? value
    : undefined;
}
