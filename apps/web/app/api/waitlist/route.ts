import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { readBoundedJsonObject } from "@/lib/boundedJson";
import { createAdminSupabaseClient } from "@/lib/supabaseAdmin";
import {
  normalizedUserAgent,
  normalizeWaitlistEmail,
  parseAllowedHostnames,
  resolveTrustedClientIp,
  TURNSTILE_SECRET_MIN_LENGTH,
  TURNSTILE_TOKEN_MAX_LENGTH,
  verifyTurnstileToken,
  WAITLIST_BODY_LIMIT_BYTES,
  waitlistIpHash,
} from "@/lib/waitlistSecurity";

type WaitlistErrorOptions = {
  retryAfterSeconds?: number;
};

export async function POST(request: Request) {
  const requestId = randomUUID();
  try {
    return await handleWaitlistPost(request, requestId);
  } catch (error) {
    console.error(JSON.stringify({
      event: "waitlist_request_failed",
      request_id: requestId,
      error_name: error instanceof Error ? error.name : typeof error,
    }));
    return waitlistError(
      requestId,
      500,
      "internal_error",
      "Could not join the beta list. Please try again.",
    );
  }
}

async function handleWaitlistPost(request: Request, requestId: string) {
  const parsed = await readBoundedJsonObject(
    request,
    WAITLIST_BODY_LIMIT_BYTES,
  );
  if (!parsed.ok) {
    return waitlistError(
      requestId,
      parsed.status,
      parsed.code,
      parsed.message,
    );
  }

  const email = normalizeWaitlistEmail(parsed.value.email);
  if (!email) {
    return waitlistError(
      requestId,
      400,
      "invalid_email",
      "Enter a valid email address to join the beta list.",
    );
  }

  const turnstileToken = typeof parsed.value.turnstile_token === "string"
    ? parsed.value.turnstile_token
    : "";
  if (
    turnstileToken.length < 1 ||
    turnstileToken.length > TURNSTILE_TOKEN_MAX_LENGTH
  ) {
    return waitlistError(
      requestId,
      400,
      "invalid_challenge",
      "Complete the security check and try again.",
    );
  }

  const trustedIpHeader = configuredTrustedIpHeader();
  const clientIp = trustedIpHeader
    ? resolveTrustedClientIp(request.headers, trustedIpHeader)
    : null;
  const ipHashSecret = process.env.WAITLIST_IP_HASH_SECRET ?? "";
  const ipHash = clientIp ? waitlistIpHash(clientIp, ipHashSecret) : null;
  const allowedHostnames = parseAllowedHostnames(
    process.env.TURNSTILE_ALLOWED_HOSTNAMES,
  );
  const turnstileSecret = process.env.TURNSTILE_SECRET_KEY ?? "";

  if (
    !clientIp ||
    !ipHash ||
    allowedHostnames.size < 1 ||
    turnstileSecret.length < TURNSTILE_SECRET_MIN_LENGTH
  ) {
    console.error(JSON.stringify({
      event: "waitlist_security_configuration_unavailable",
      request_id: requestId,
      has_client_ip: Boolean(clientIp),
      has_ip_hash_secret: ipHashSecret.length >= 32,
      has_allowed_hostname: allowedHostnames.size > 0,
      has_turnstile_secret:
        turnstileSecret.length >= TURNSTILE_SECRET_MIN_LENGTH,
    }));
    return waitlistError(
      requestId,
      503,
      "waitlist_unavailable",
      "The beta list is temporarily unavailable. Please try again later.",
    );
  }

  const supabase = createAdminSupabaseClient();
  if (!supabase) {
    console.error(JSON.stringify({
      event: "waitlist_database_configuration_unavailable",
      request_id: requestId,
    }));
    return waitlistError(
      requestId,
      503,
      "waitlist_unavailable",
      "The beta list is temporarily unavailable. Please try again later.",
    );
  }

  const { error: challengeRateError } = await supabase.rpc(
    "claim_beta_waitlist_challenge_attempt",
    { p_ip_hash: ipHash },
  );
  if (challengeRateError) {
    const rateLimited = challengeRateError.message.includes(
      "waitlist_challenge_rate_limited",
    );
    console.error(JSON.stringify({
      event: rateLimited
        ? "waitlist_challenge_rate_limited"
        : "waitlist_challenge_rate_claim_failed",
      request_id: requestId,
      database_code: challengeRateError.code ?? null,
    }));
    if (rateLimited) {
      return waitlistError(
        requestId,
        429,
        "rate_limited",
        "Too many signup attempts. Please try again later.",
        { retryAfterSeconds: 600 },
      );
    }
    return waitlistError(
      requestId,
      503,
      "waitlist_unavailable",
      "The beta list is temporarily unavailable. Please try again later.",
    );
  }

  const challenge = await verifyTurnstileToken({
    token: turnstileToken,
    secret: turnstileSecret,
    remoteIp: clientIp,
    requestId,
    allowedHostnames,
  });
  if (!challenge.ok) {
    if (challenge.kind === "unavailable") {
      console.error(JSON.stringify({
        event: "waitlist_challenge_unavailable",
        request_id: requestId,
      }));
      return waitlistError(
        requestId,
        503,
        "challenge_unavailable",
        "The security check is temporarily unavailable. Please try again.",
      );
    }
    return waitlistError(
      requestId,
      400,
      "invalid_challenge",
      "Complete the security check and try again.",
    );
  }

  const { error } = await supabase.rpc("submit_beta_waitlist_signup", {
    p_email: email,
    p_ip_hash: ipHash,
    p_source: "web_waitlist",
    p_user_agent: normalizedUserAgent(request.headers.get("user-agent")),
  });

  if (error) {
    const rateLimited = error.message.includes("waitlist_ip_rate_limited") ||
      error.message.includes("waitlist_global_rate_limited");
    console.error(JSON.stringify({
      event: rateLimited
        ? "waitlist_signup_rate_limited"
        : "waitlist_signup_failed",
      request_id: requestId,
      database_code: error.code ?? null,
    }));
    if (rateLimited) {
      return waitlistError(
        requestId,
        429,
        "rate_limited",
        "Too many signup attempts. Please try again later.",
        { retryAfterSeconds: 600 },
      );
    }
    return waitlistError(
      requestId,
      500,
      "internal_error",
      "Could not join the beta list. Please try again.",
    );
  }

  return NextResponse.json(
    {
      message: "You are on the Naturebook beta list. We will be in touch soon.",
      request_id: requestId,
    },
    {
      headers: {
        "Cache-Control": "private, no-store",
        "X-Request-ID": requestId,
      },
    },
  );
}

function configuredTrustedIpHeader(): string {
  const configured = process.env.WAITLIST_TRUSTED_IP_HEADER?.trim();
  if (configured) return configured;
  if (process.env.VERCEL === "1") return "x-vercel-forwarded-for";
  return process.env.NODE_ENV === "production" ? "" : "x-forwarded-for";
}

function waitlistError(
  requestId: string,
  status: number,
  code: string,
  message: string,
  options: WaitlistErrorOptions = {},
) {
  const retryAfter = options.retryAfterSeconds;
  return NextResponse.json(
    {
      message,
      code,
      request_id: requestId,
      ...(retryAfter ? { retry_after_seconds: retryAfter } : {}),
    },
    {
      status,
      headers: {
        "Cache-Control": "private, no-store",
        "X-Request-ID": requestId,
        ...(retryAfter ? { "Retry-After": String(retryAfter) } : {}),
      },
    },
  );
}
