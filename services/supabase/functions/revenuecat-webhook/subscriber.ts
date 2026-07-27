import {
  isSevenDayPassProduct,
  SEVEN_DAY_PASS_DURATION_MS,
  SEVEN_DAY_PASS_PRODUCT_ID,
} from "../_shared/subscriptionPass.ts";
import { readByteStreamWithinLimit } from "../_shared/http.ts";
import { fetchWithDeadline } from "../_shared/outbound.ts";
import { RevenueCatWebhookEvent } from "./protocol.ts";

const REVENUECAT_API_BASE_URL = "https://api.revenuecat.com/v1";
const MAX_CUSTOMER_INFO_BYTES = 2 * 1024 * 1024;
const CUSTOMER_INFO_TIMEOUT_MS = 10_000;
const MAX_POSTGRES_TIMESTAMP_MS = 253_402_300_799_999;
const PAID_ENTITLEMENT_IDS = new Set(["Naturalist Tier", "pro"]);
const PASS_REVOCATION_EVENTS = new Set([
  "CANCELLATION",
  "EXPIRATION",
  "REFUND",
]);

export class RevenueCatApiError extends Error {
  constructor(message: string, readonly retryable: boolean) {
    super(message);
    this.name = "RevenueCatApiError";
  }
}

export interface RevenueCatCustomerInfo {
  requestDateMs: number;
  subscriber: Record<string, unknown>;
}

export interface RevenueCatEntitlementState {
  targetTier: "free" | "pro";
  expiresAt: string | null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function parseDateMs(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function activeEntitlementExpiration(
  entitlement: unknown,
  snapshotAtMs: number,
): number | null | undefined {
  if (!isRecord(entitlement)) return undefined;
  // RevenueCat reserves a null expiration for genuinely non-expiring
  // entitlements (for example, a lifetime product).
  if (entitlement.expires_date === null) return null;

  const expiresAtMs = parseDateMs(entitlement.expires_date);
  const gracePeriodExpiresAtMs = parseDateMs(
    entitlement.grace_period_expires_date,
  );
  const accessEndsAtMs = Math.max(
    expiresAtMs ?? 0,
    gracePeriodExpiresAtMs ?? 0,
  );
  return accessEndsAtMs > snapshotAtMs ? accessEndsAtMs : undefined;
}

function revokedPassTransactionIds(
  event: RevenueCatWebhookEvent | undefined,
): Set<string> {
  if (
    !event ||
    !isSevenDayPassProduct(event.productId) ||
    !PASS_REVOCATION_EVENTS.has(event.type)
  ) {
    return new Set();
  }
  return new Set(
    [event.transactionId, event.originalTransactionId].filter(
      (value): value is string => value !== null,
    ),
  );
}

function activePassExpiration(
  subscriber: Record<string, unknown>,
  snapshotAtMs: number,
  event: RevenueCatWebhookEvent | undefined,
): number | null {
  const nonSubscriptions = subscriber.non_subscriptions;
  if (!isRecord(nonSubscriptions)) return null;

  const transactions = nonSubscriptions[SEVEN_DAY_PASS_PRODUCT_ID];
  if (!Array.isArray(transactions)) return null;

  const revocationEvent = event !== undefined &&
    isSevenDayPassProduct(event.productId) &&
    PASS_REVOCATION_EVENTS.has(event.type);
  const revokedIds = revokedPassTransactionIds(event);
  const hasExplicitRevocationMatch = revokedIds.size > 0 &&
    transactions.some((transaction) =>
      isRecord(transaction) &&
      typeof transaction.id === "string" &&
      revokedIds.has(transaction.id)
    );
  let latestExpiration: number | null = null;

  for (const transaction of transactions) {
    if (!isRecord(transaction)) continue;
    const transactionId = typeof transaction.id === "string"
      ? transaction.id
      : null;
    const purchaseAtMs = parseDateMs(transaction.purchase_date);
    if (
      purchaseAtMs === null ||
      purchaseAtMs < 0 ||
      purchaseAtMs > snapshotAtMs ||
      purchaseAtMs > MAX_POSTGRES_TIMESTAMP_MS - SEVEN_DAY_PASS_DURATION_MS
    ) {
      continue;
    }

    const explicitlyRevoked = transactionId !== null &&
      revokedIds.has(transactionId);
    const conservativelyRevoked = revocationEvent &&
      !hasExplicitRevocationMatch &&
      purchaseAtMs <= (event?.eventTimestampMs ?? -1);
    if (explicitlyRevoked || conservativelyRevoked) continue;

    const expiresAtMs = purchaseAtMs + SEVEN_DAY_PASS_DURATION_MS;
    if (
      expiresAtMs > snapshotAtMs &&
      (latestExpiration === null || expiresAtMs > latestExpiration)
    ) {
      latestExpiration = expiresAtMs;
    }
  }

  return latestExpiration;
}

async function readBoundedResponseBody(
  response: Response,
): Promise<Uint8Array> {
  const result = await readByteStreamWithinLimit(
    response.body,
    MAX_CUSTOMER_INFO_BYTES,
    "CustomerInfo response exceeded limit",
  );
  if (result.exceeded || !result.bytes) {
    throw new RevenueCatApiError(
      "RevenueCat CustomerInfo response exceeded the size limit.",
      true,
    );
  }
  return result.bytes;
}

export function deriveRevenueCatEntitlementState(
  customerInfo: RevenueCatCustomerInfo,
  event?: RevenueCatWebhookEvent,
  allowNonSubscriptionPassGrant = true,
): RevenueCatEntitlementState {
  const entitlements = customerInfo.subscriber.entitlements;
  let latestRecurringExpiration: number | undefined;
  if (isRecord(entitlements)) {
    for (const [entitlementId, entitlement] of Object.entries(entitlements)) {
      if (!PAID_ENTITLEMENT_IDS.has(entitlementId)) continue;
      const expiration = activeEntitlementExpiration(
        entitlement,
        customerInfo.requestDateMs,
      );
      if (expiration === null) {
        return { targetTier: "pro", expiresAt: null };
      }
      if (
        expiration !== undefined &&
        (latestRecurringExpiration === undefined ||
          expiration > latestRecurringExpiration)
      ) {
        latestRecurringExpiration = expiration;
      }
    }
  }
  if (latestRecurringExpiration !== undefined) {
    return {
      targetTier: "pro",
      expiresAt: new Date(latestRecurringExpiration).toISOString(),
    };
  }

  // CustomerInfo retains historical non-renewing purchases after a refund.
  // Webhook deliveries carry the revocation event needed to distinguish that
  // history. A periodic repair may grant a pass only when the database claim
  // proves there is no prior free/revoked watermark to overwrite.
  if (!allowNonSubscriptionPassGrant) {
    return { targetTier: "free", expiresAt: null };
  }

  const passExpiration = activePassExpiration(
    customerInfo.subscriber,
    customerInfo.requestDateMs,
    event,
  );
  if (passExpiration !== null) {
    return {
      targetTier: "pro",
      expiresAt: new Date(passExpiration).toISOString(),
    };
  }

  return { targetTier: "free", expiresAt: null };
}

export async function fetchRevenueCatCustomerInfo(
  appUserId: string,
  apiKey: string,
  fetchImpl: typeof fetch = fetch,
): Promise<RevenueCatCustomerInfo> {
  let response: Response;
  try {
    response = await fetchWithDeadline(
      `${REVENUECAT_API_BASE_URL}/subscribers/${encodeURIComponent(appUserId)}`,
      {
        method: "GET",
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
      },
      { fetcher: fetchImpl, timeoutMs: CUSTOMER_INFO_TIMEOUT_MS },
    );
  } catch (error) {
    const detail = error instanceof Error ? error.message : "network failure";
    throw new RevenueCatApiError(
      `RevenueCat CustomerInfo request failed: ${detail}`,
      true,
    );
  }

  try {
    if (!response.ok) {
      const retryable = response.status === 408 ||
        response.status === 425 ||
        response.status === 429 ||
        response.status >= 500;
      await response.body?.cancel().catch(() => undefined);
      throw new RevenueCatApiError(
        `RevenueCat CustomerInfo returned HTTP ${response.status}.`,
        retryable,
      );
    }

    const contentLength = Number(response.headers.get("Content-Length"));
    if (
      Number.isFinite(contentLength) &&
      contentLength > MAX_CUSTOMER_INFO_BYTES
    ) {
      await response.body?.cancel().catch(() => undefined);
      throw new RevenueCatApiError(
        "RevenueCat CustomerInfo response exceeded the size limit.",
        true,
      );
    }

    const rawBytes = await readBoundedResponseBody(response);
    let rawBody: string;
    try {
      rawBody = new TextDecoder("utf-8", { fatal: true }).decode(rawBytes);
    } catch {
      throw new RevenueCatApiError(
        "RevenueCat CustomerInfo returned invalid UTF-8.",
        true,
      );
    }

    let payload: unknown;
    try {
      payload = JSON.parse(rawBody);
    } catch {
      throw new RevenueCatApiError(
        "RevenueCat CustomerInfo returned invalid JSON.",
        true,
      );
    }

    if (
      !isRecord(payload) ||
      typeof payload.request_date_ms !== "number" ||
      !Number.isSafeInteger(payload.request_date_ms) ||
      payload.request_date_ms < 0 ||
      payload.request_date_ms > 253_402_300_799_999 ||
      !isRecord(payload.subscriber)
    ) {
      throw new RevenueCatApiError(
        "RevenueCat CustomerInfo response was missing required fields.",
        true,
      );
    }

    return {
      requestDateMs: payload.request_date_ms,
      subscriber: payload.subscriber,
    };
  } catch (error) {
    if (error instanceof RevenueCatApiError) throw error;
    const detail = error instanceof Error ? error.message : "response failure";
    throw new RevenueCatApiError(
      `RevenueCat CustomerInfo response failed: ${detail}`,
      true,
    );
  }
}
