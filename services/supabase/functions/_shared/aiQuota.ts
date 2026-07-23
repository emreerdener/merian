import type { SupabaseClient } from "@supabase/supabase-js";
import { logStructuredError } from "./edgeHandler.ts";
import type { TierResolution } from "./entitlement.ts";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const IP_HASH_PATTERN = /^[0-9a-f]{64}$/;
const SUPPORTED_MODELS = new Set([
  "gemini-2.5-flash",
  "gemini-2.5-pro",
]);

export type AIQuotaOperation =
  | "scan_identification"
  | "scan_audio_identification"
  | "scan_overview_enrichment"
  | "scan_lookalike_enrichment"
  | "scan_group_tag_enrichment"
  | "explore_audio_moderation"
  | "insight_chat_reply"
  | "insight_chat_prompt_suggestions"
  | "insight_chat_summary"
  | "explore_post_chat_reply";

interface AIQuotaReservationRow {
  reservation_id: string;
  request_id: string;
  lease_token: string;
  lease_expires_at: string;
  reservation_state: "reserved" | "committed" | "failed" | "refunded";
  is_replay: boolean;
  attempt_count: number;
  model: string;
  effective_plan: "free" | "pro_trial" | "pro_paid";
  effective_tier: "free" | "pro";
  subscription_tier: "free" | "pro";
  trial_active: boolean;
  entitlement_version: number;
  policy_version: number;
  daily_limit: number | null;
  daily_remaining: number | null;
}

export interface AIQuotaReservation {
  id: string;
  requestId: string;
  leaseToken: string;
  leaseExpiresAt: string;
  attemptCount: number;
  model: "gemini-2.5-flash" | "gemini-2.5-pro";
  tier: TierResolution;
  policyVersion: number;
  dailyLimit: number | null;
  dailyRemaining: number | null;
}

export interface AIProviderQuotaLease {
  reservation: AIQuotaReservation;
  commit(): Promise<void>;
  refund(): Promise<boolean>;
  fail(): Promise<boolean>;
}

export class AIQuotaError extends Error {
  readonly status: number;
  readonly code: string;
  readonly retryAfterSeconds?: number;

  constructor(
    status: number,
    code: string,
    message: string,
    retryAfterSeconds?: number,
  ) {
    super(message);
    this.name = "AIQuotaError";
    this.status = status;
    this.code = code;
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

function invalidRequest(message: string): AIQuotaError {
  return new AIQuotaError(400, "ai_request_id_invalid", message);
}

export function resolveAIRequestId(
  req: Request,
  candidate?: unknown,
): string {
  if (candidate != null) {
    if (typeof candidate !== "string" || !UUID_PATTERN.test(candidate.trim())) {
      throw invalidRequest("AI request id must be a UUID.");
    }
    return candidate.trim().toLowerCase();
  }

  const headerValue = req.headers.get("Idempotency-Key")?.trim();
  if (headerValue) {
    if (!UUID_PATTERN.test(headerValue)) {
      throw invalidRequest("Idempotency-Key must be a UUID.");
    }
    return headerValue.toLowerCase();
  }

  return crypto.randomUUID();
}

/**
 * Derives a stable UUID for one paid sub-operation within an idempotent request.
 *
 * This lets a route reserve independently for multiple media items while
 * preserving the caller's retry key. Only the digest-derived UUID reaches the
 * quota ledger; the discriminator itself is never persisted.
 */
export async function deriveAIRequestId(
  parentRequestId: string,
  discriminator: string,
): Promise<string> {
  if (
    !UUID_PATTERN.test(parentRequestId) ||
    discriminator.length === 0 ||
    discriminator.length > 512
  ) {
    throw invalidRequest("AI request id derivation input is invalid.");
  }

  const digest = new Uint8Array(
    await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(
        `${parentRequestId.toLowerCase()}:${discriminator}`,
      ),
    ),
  ).slice(0, 16);
  // RFC 9562 UUIDv8: application-defined digest payload with the standard
  // variant bits. This is deterministic but carries no reversible media data.
  digest[6] = (digest[6] & 0x0f) | 0x80;
  digest[8] = (digest[8] & 0x3f) | 0x80;
  const hex = Array.from(
    digest,
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${
    hex.slice(16, 20)
  }-${hex.slice(20)}`;
}

export function clientAddressForQuota(headers: Headers): string {
  const realIp = headers.get("x-real-ip")?.trim();
  if (realIp) return realIp.slice(0, 128).toLowerCase();

  const connectingIp = headers.get("cf-connecting-ip")?.trim();
  if (connectingIp) return connectingIp.slice(0, 128).toLowerCase();

  // Use the right-most value. Proxies append their observed peer, while a
  // caller-controlled left-most value must never choose the quota bucket.
  const forwarded = headers.get("x-forwarded-for")
    ?.split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  const forwardedPeer = forwarded?.at(-1);
  if (forwardedPeer) return forwardedPeer.slice(0, 128).toLowerCase();

  // Hosted Edge requests normally include x-real-ip. Sharing one fail-safe
  // bucket when it is unavailable is safer than silently disabling IP limits.
  return "unavailable";
}

export async function hmacClientAddress(
  address: string,
  secret: string,
  now = new Date(),
): Promise<string> {
  if (secret.trim().length < 32) {
    throw new AIQuotaError(
      503,
      "ai_quota_unavailable",
      "AI service is temporarily unavailable.",
    );
  }
  const day = now.toISOString().slice(0, 10);
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      encoder.encode(`merian-ai-quota-ip-v1:${day}:${address}`),
    ),
  );
  return Array.from(
    signature,
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

export function resolveQuotaIpHashSecret(input: {
  dedicatedSecret?: string | null;
  platformSecretKey?: string | null;
  serviceRoleKey?: string | null;
}): string {
  const dedicated = input.dedicatedSecret?.trim();
  if (dedicated) {
    if (dedicated.length < 32) {
      throw new AIQuotaError(
        503,
        "ai_quota_unavailable",
        "AI service is temporarily unavailable.",
      );
    }
    return dedicated;
  }

  const platformSecret = input.platformSecretKey?.trim() ||
    input.serviceRoleKey?.trim();
  if (!platformSecret || platformSecret.length < 32) {
    throw new AIQuotaError(
      503,
      "ai_quota_unavailable",
      "AI service is temporarily unavailable.",
    );
  }
  return platformSecret;
}

async function quotaIpHash(req: Request): Promise<string> {
  const secret = resolveQuotaIpHashSecret({
    dedicatedSecret: Deno.env.get("AI_QUOTA_IP_HASH_SECRET"),
    platformSecretKey: Deno.env.get("SUPABASE_SECRET_KEY"),
    serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
  });
  const hash = await hmacClientAddress(
    clientAddressForQuota(req.headers),
    secret,
  );
  if (!IP_HASH_PATTERN.test(hash)) {
    throw new AIQuotaError(
      503,
      "ai_quota_unavailable",
      "AI service is temporarily unavailable.",
    );
  }
  return hash;
}

function quotaErrorForDatabaseMessage(
  databaseMessage: string,
): AIQuotaError {
  if (databaseMessage.includes("ai_entitlement_required")) {
    return new AIQuotaError(
      402,
      "pro_required",
      "This AI feature requires Naturebook Pro.",
    );
  }
  if (databaseMessage.includes("ai_quota_daily_exceeded")) {
    return new AIQuotaError(
      429,
      "ai_quota_daily_exceeded",
      "Daily AI limit reached.",
      3600,
    );
  }
  if (databaseMessage.includes("ai_user_rate_limit_exceeded")) {
    return new AIQuotaError(
      429,
      "ai_user_rate_limit_exceeded",
      "Too many AI requests. Try again shortly.",
      60,
    );
  }
  if (databaseMessage.includes("ai_ip_rate_limit_exceeded")) {
    return new AIQuotaError(
      429,
      "ai_ip_rate_limit_exceeded",
      "Too many AI requests from this network. Try again shortly.",
      60,
    );
  }
  if (databaseMessage.includes("ai_quota_invalid_request")) {
    return invalidRequest("AI quota request is invalid.");
  }
  return new AIQuotaError(
    503,
    "ai_entitlement_unavailable",
    "AI entitlement could not be verified. Please try again.",
    30,
  );
}

function singleReservationRow(data: unknown): AIQuotaReservationRow | null {
  if (Array.isArray(data) && data.length !== 1) return null;
  const value = Array.isArray(data) ? data[0] : data;
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as AIQuotaReservationRow;
}

export async function reserveAIQuota(
  req: Request,
  supabaseAdmin: SupabaseClient,
  input: {
    userId: string;
    operation: AIQuotaOperation;
    requestId?: unknown;
  },
): Promise<AIQuotaReservation> {
  const requestId = resolveAIRequestId(req, input.requestId);
  const ipHash = await quotaIpHash(req);
  const { data, error } = await (async () => {
    try {
      return await supabaseAdmin.rpc("reserve_ai_quota", {
        p_user_id: input.userId,
        p_operation: input.operation,
        p_request_id: requestId,
        p_ip_hash: ipHash,
      }).abortSignal(AbortSignal.timeout(5_000));
    } catch {
      logStructuredError("ai_quota_reservation_failed", {
        operation: input.operation,
        code: "ai_entitlement_unavailable",
        database_code: null,
      });
      throw new AIQuotaError(
        503,
        "ai_entitlement_unavailable",
        "AI entitlement could not be verified. Please try again.",
        30,
      );
    }
  })();

  if (error) {
    const quotaError = quotaErrorForDatabaseMessage(error.message);
    logStructuredError("ai_quota_reservation_failed", {
      operation: input.operation,
      code: quotaError.code,
      database_code: error.code ?? null,
    });
    throw quotaError;
  }

  const row = singleReservationRow(data);
  const leaseExpiryMs = row == null
    ? Number.NaN
    : Date.parse(row.lease_expires_at);
  if (
    !row ||
    !UUID_PATTERN.test(row.reservation_id) ||
    !UUID_PATTERN.test(row.request_id) ||
    !UUID_PATTERN.test(row.lease_token) ||
    !Number.isFinite(leaseExpiryMs) ||
    row.request_id.toLowerCase() !== requestId ||
    (row.reservation_state !== "reserved" &&
      row.reservation_state !== "committed" &&
      row.reservation_state !== "failed" &&
      row.reservation_state !== "refunded") ||
    typeof row.is_replay !== "boolean" ||
    !Number.isSafeInteger(row.attempt_count) ||
    row.attempt_count < 1 ||
    !SUPPORTED_MODELS.has(row.model) ||
    (row.effective_plan !== "free" &&
      row.effective_plan !== "pro_trial" &&
      row.effective_plan !== "pro_paid") ||
    (row.effective_tier !== "free" && row.effective_tier !== "pro") ||
    (row.subscription_tier !== "free" &&
      row.subscription_tier !== "pro") ||
    typeof row.trial_active !== "boolean" ||
    !Number.isSafeInteger(row.entitlement_version) ||
    row.entitlement_version < 1 ||
    !Number.isSafeInteger(row.policy_version) ||
    row.policy_version < 1 ||
    (row.daily_limit !== null &&
      (!Number.isSafeInteger(row.daily_limit) || row.daily_limit < 1)) ||
    (row.daily_remaining !== null &&
      (!Number.isSafeInteger(row.daily_remaining) ||
        row.daily_remaining < 0)) ||
    (row.daily_limit === null && row.daily_remaining !== null) ||
    (row.daily_limit !== null &&
      row.daily_remaining !== null &&
      row.daily_remaining > row.daily_limit) ||
    (row.is_replay
      ? row.reservation_state !== "reserved" &&
        row.reservation_state !== "committed"
      : row.reservation_state !== "reserved") ||
    (row.effective_plan === "free"
      ? row.effective_tier !== "free" ||
        row.subscription_tier !== "free" ||
        row.trial_active
      : row.effective_tier !== "pro") ||
    (row.effective_plan === "pro_trial" &&
      (row.subscription_tier !== "free" || !row.trial_active)) ||
    (row.effective_plan === "pro_paid" &&
      (row.subscription_tier !== "pro" || row.trial_active))
  ) {
    logStructuredError("ai_quota_reservation_invalid_response", {
      operation: input.operation,
    });
    throw new AIQuotaError(
      503,
      "ai_quota_unavailable",
      "AI service is temporarily unavailable.",
    );
  }

  if (row.is_replay) {
    const code = row.reservation_state === "committed"
      ? "ai_request_already_completed"
      : "ai_request_in_progress";
    const retryAfterSeconds = row.reservation_state === "reserved"
      ? Math.max(
        1,
        Math.min(600, Math.ceil((leaseExpiryMs - Date.now()) / 1_000)),
      )
      : undefined;
    throw new AIQuotaError(
      409,
      code,
      row.reservation_state === "committed"
        ? "This AI request was already completed."
        : "This AI request is already in progress.",
      retryAfterSeconds,
    );
  }

  return {
    id: row.reservation_id,
    requestId: row.request_id,
    leaseToken: row.lease_token,
    leaseExpiresAt: row.lease_expires_at,
    attemptCount: row.attempt_count,
    model: row.model as AIQuotaReservation["model"],
    tier: {
      effective_tier: row.effective_tier,
      plan: row.effective_plan,
      subscription_tier: row.subscription_tier,
      trial_active: row.trial_active,
      user_exists: true,
      entitlement_version: row.entitlement_version,
    },
    policyVersion: row.policy_version,
    dailyLimit: row.daily_limit,
    dailyRemaining: row.daily_remaining,
  };
}

async function finalizeReservation(
  supabaseAdmin: SupabaseClient,
  userId: string,
  reservation: AIQuotaReservation,
  finalState: "committed" | "failed" | "refunded",
): Promise<boolean> {
  let data: unknown;
  let error: { code?: string } | null;
  try {
    const result = await supabaseAdmin.rpc(
      "finalize_ai_quota_reservation",
      {
        p_reservation_id: reservation.id,
        p_user_id: userId,
        p_lease_token: reservation.leaseToken,
        p_final_state: finalState,
      },
    ).abortSignal(AbortSignal.timeout(5_000));
    data = result.data;
    error = result.error;
  } catch {
    logStructuredError("ai_quota_finalization_failed", {
      final_state: finalState,
      database_code: null,
    });
    return false;
  }

  if (error || data !== true) {
    logStructuredError("ai_quota_finalization_failed", {
      final_state: finalState,
      database_code: error?.code ?? null,
    });
    return false;
  }
  return true;
}

export function createAIProviderQuotaLease(
  supabaseAdmin: SupabaseClient,
  userId: string,
  reservation: AIQuotaReservation,
): AIProviderQuotaLease {
  let finalState: "committed" | "failed" | "refunded" | null = null;

  return {
    reservation,
    async commit() {
      if (finalState === "committed") return;
      if (finalState !== null) {
        throw new AIQuotaError(
          503,
          "ai_quota_unavailable",
          "AI service is temporarily unavailable.",
        );
      }
      const finalized = await finalizeReservation(
        supabaseAdmin,
        userId,
        reservation,
        "committed",
      );
      if (!finalized) {
        throw new AIQuotaError(
          503,
          "ai_quota_unavailable",
          "AI service is temporarily unavailable.",
        );
      }
      finalState = "committed";
    },
    async refund() {
      if (finalState) return finalState === "refunded";
      const finalized = await finalizeReservation(
        supabaseAdmin,
        userId,
        reservation,
        "refunded",
      );
      if (finalized) finalState = "refunded";
      return finalized;
    },
    async fail() {
      if (finalState === "failed") return true;
      if (finalState !== "committed") return false;
      const finalized = await finalizeReservation(
        supabaseAdmin,
        userId,
        reservation,
        "failed",
      );
      if (finalized) finalState = "failed";
      return finalized;
    },
  };
}

export async function reserveAIProviderCall(
  req: Request,
  supabaseAdmin: SupabaseClient,
  input: {
    userId: string;
    operation: AIQuotaOperation;
    requestId?: unknown;
  },
): Promise<AIProviderQuotaLease> {
  const reservation = await reserveAIQuota(req, supabaseAdmin, input);
  return createAIProviderQuotaLease(
    supabaseAdmin,
    input.userId,
    reservation,
  );
}
