import { createClient, SupabaseClient, User } from "@supabase/supabase-js";
import { requireAuth } from "./auth.ts";
import { corsHeaders, jsonResponse } from "./http.ts";

export { jsonResponse };

export type EdgeAuthenticator = (
  req: Request,
  supabaseAdmin: SupabaseClient,
) => Promise<{ user: User | null; response: Response | null }>;

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
    event,
    ts: new Date().toISOString(),
    ...details,
  }));
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
    task.catch(console.error);
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
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const authStart = performance.now();
    const authenticate = options.authenticate ?? requireAuth;
    const { user, response } = await authenticate(req, supabaseAdmin);
    const authDuration = performance.now() - authStart;

    if (response || !user) {
      return withAuthServerTiming(
        response || jsonResponse({ error: "Unauthorized" }, 401),
        authDuration,
      );
    }

    return withAuthServerTiming(
      await handler(user, supabaseAdmin, { authDurationMs: authDuration }),
      authDuration,
    );
  } catch (error: unknown) {
    console.error("Edge function error:", error);
    const msg = error instanceof Error
      ? error.message
      : "Internal Server Error";
    const errorRecord = error && typeof error === "object"
      ? error as Record<string, unknown>
      : {};
    const candidateStatus = errorRecord.status;
    const customStatus = typeof candidateStatus === "number" &&
        Number.isInteger(candidateStatus) &&
        candidateStatus >= 400 && candidateStatus <= 599
      ? candidateStatus
      : 500;
    const candidateCode = errorRecord.code;
    const code = typeof candidateCode === "string" &&
        /^[a-z][a-z0-9_]{1,63}$/.test(candidateCode)
      ? candidateCode
      : undefined;
    const candidateRetryAfter = errorRecord.retryAfterSeconds;
    const retryAfter = typeof candidateRetryAfter === "number" &&
        Number.isInteger(candidateRetryAfter) &&
        candidateRetryAfter > 0 &&
        candidateRetryAfter <= 86400
      ? candidateRetryAfter
      : undefined;
    return jsonResponse(
      {
        error: msg,
        ...(code ? { code } : {}),
        ...(retryAfter ? { retry_after_seconds: retryAfter } : {}),
      },
      customStatus,
      retryAfter ? { "Retry-After": String(retryAfter) } : {},
    );
  }
}

function withAuthServerTiming(
  response: Response,
  durationMs: number,
): Response {
  const headers = new Headers(response.headers);
  const existing = headers.get("Server-Timing");
  const authMetric = `auth;dur=${Math.max(durationMs, 0).toFixed(1)}`;
  headers.set(
    "Server-Timing",
    existing ? `${authMetric}, ${existing}` : authMetric,
  );
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
