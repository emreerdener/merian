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
const STOREKIT_PRO_SUBSCRIPTION_PRODUCT_IDS = new Set(["pro_annual"]);
const PASS_REVOCATION_EVENTS = new Set([
  "CANCELLATION",
  "EXPIRATION",
  "REFUND",
]);
const PASS_PURCHASE_EVENTS = new Set(["NON_RENEWING_PURCHASE"]);

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

/**
 * Returns whether one active access horizon fully covers another. A null Pro
 * expiration is lifetime; a free source requires no destination access.
 */
export function revenueCatAccessCovers(
  target: RevenueCatEntitlementState,
  source: RevenueCatEntitlementState,
): boolean {
  if (source.targetTier === "free") return true;
  if (target.targetTier !== "pro") return false;
  if (target.expiresAt === null) return true;
  if (source.expiresAt === null) return false;
  const targetExpiration = Date.parse(target.expiresAt);
  const sourceExpiration = Date.parse(source.expiresAt);
  return Number.isFinite(targetExpiration) &&
    Number.isFinite(sourceExpiration) &&
    targetExpiration >= sourceExpiration;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isAppStorePurchaseRecord(value: unknown): boolean {
  // RevenueCat v1 uses the lowercase `app_store` discriminator. Promotional
  // grants are represented as subscription records with `store: promotional`,
  // so presence in `subscriptions` alone is not evidence of a StoreKit receipt.
  // Unknown or missing stores fail closed at the sign-out transfer boundary.
  return isRecord(value) && value.store === "app_store";
}

function isPromotionalPurchaseRecord(value: unknown): boolean {
  return isRecord(value) && value.store === "promotional";
}

/**
 * Parses the CustomerInfo shape returned by RevenueCat v1. The OpenAPI
 * renderer wraps some response examples in `value`, while live endpoints may
 * return the CustomerInfo object directly, so both documented shapes are
 * accepted and everything else fails closed.
 */
export function parseRevenueCatCustomerInfoPayload(
  payload: unknown,
): RevenueCatCustomerInfo {
  const root = isRecord(payload) && isRecord(payload.value)
    ? payload.value
    : payload;
  if (
    !isRecord(root) ||
    typeof root.request_date_ms !== "number" ||
    !Number.isSafeInteger(root.request_date_ms) ||
    root.request_date_ms < 0 ||
    root.request_date_ms > MAX_POSTGRES_TIMESTAMP_MS ||
    !isRecord(root.subscriber)
  ) {
    throw new RevenueCatApiError(
      "RevenueCat CustomerInfo response was missing required fields.",
      true,
    );
  }

  return {
    requestDateMs: root.request_date_ms,
    subscriber: root.subscriber,
  };
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
  requireAppStoreTransaction = false,
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
    if (
      requireAppStoreTransaction && !isAppStorePurchaseRecord(transaction)
    ) {
      continue;
    }
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

export async function readRevenueCatCustomerInfoResponse(
  response: Response,
): Promise<RevenueCatCustomerInfo> {
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
  return parseRevenueCatCustomerInfoPayload(payload);
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

/**
 * Derives only active access backed by an App Store/StoreKit transaction.
 * RevenueCat promotional grants can appear in both `entitlements` and
 * `subscriptions`, but their subscription record uses `store: promotional`.
 * Requiring an explicit `store: app_store` purchase record prevents a normal
 * app sign-out from cloning account-bound beta/operator access onto a second
 * customer. Unknown or missing stores fail closed. The detached `pro_week`
 * StoreKit purchase remains eligible only with the same App Store evidence.
 */
export function deriveRevenueCatStoreEntitlementState(
  customerInfo: RevenueCatCustomerInfo,
  allowNonSubscriptionPassGrant = true,
  event?: RevenueCatWebhookEvent,
): RevenueCatEntitlementState {
  const subscriptions = isRecord(customerInfo.subscriber.subscriptions)
    ? customerInfo.subscriber.subscriptions
    : {};
  const nonSubscriptions = isRecord(
      customerInfo.subscriber.non_subscriptions,
    )
    ? customerInfo.subscriber.non_subscriptions
    : {};
  const entitlements = customerInfo.subscriber.entitlements;
  let latestExpiration: number | undefined;

  // A promotional grant and an App Store subscription may target the same
  // entitlement. RevenueCat then exposes only one winning product on the
  // entitlement row even though both subscription records remain present.
  // Recognize Merian's reviewed StoreKit subscription product directly so a
  // longer promotion cannot hide paid receipt access during account rotation.
  for (
    const [productIdentifier, subscription] of Object.entries(
      subscriptions,
    )
  ) {
    if (
      !STOREKIT_PRO_SUBSCRIPTION_PRODUCT_IDS.has(productIdentifier) ||
      !isAppStorePurchaseRecord(subscription)
    ) {
      continue;
    }
    const expiration = activeEntitlementExpiration(
      subscription,
      customerInfo.requestDateMs,
    );
    // Auto-renewing subscriptions must have a finite active or grace-period
    // horizon. A missing/null expiry is malformed here, not lifetime access.
    if (
      expiration !== null && expiration !== undefined &&
      (latestExpiration === undefined || expiration > latestExpiration)
    ) {
      latestExpiration = expiration;
    }
  }

  if (isRecord(entitlements)) {
    for (const [entitlementId, entitlement] of Object.entries(entitlements)) {
      if (!PAID_ENTITLEMENT_IDS.has(entitlementId) || !isRecord(entitlement)) {
        continue;
      }
      const productIdentifier = entitlement.product_identifier;
      const subscription = typeof productIdentifier === "string"
        ? subscriptions[productIdentifier]
        : undefined;
      const nonSubscriptionPurchases = typeof productIdentifier === "string"
        ? nonSubscriptions[productIdentifier]
        : undefined;
      const hasAppStorePurchase = isAppStorePurchaseRecord(subscription) ||
        (Array.isArray(nonSubscriptionPurchases) &&
          nonSubscriptionPurchases.some(isAppStorePurchaseRecord));
      if (
        typeof productIdentifier !== "string" ||
        productIdentifier.length === 0 ||
        !hasAppStorePurchase
      ) {
        continue;
      }

      const expiration = activeEntitlementExpiration(
        entitlement,
        customerInfo.requestDateMs,
      );
      if (expiration === null) {
        return { targetTier: "pro", expiresAt: null };
      }
      if (
        expiration !== undefined &&
        (latestExpiration === undefined || expiration > latestExpiration)
      ) {
        latestExpiration = expiration;
      }
    }
  }

  const passExpiration = allowNonSubscriptionPassGrant
    ? activePassExpiration(
      customerInfo.subscriber,
      customerInfo.requestDateMs,
      event,
      true,
    )
    : null;
  if (
    passExpiration !== null &&
    (latestExpiration === undefined || passExpiration > latestExpiration)
  ) {
    latestExpiration = passExpiration;
  }

  return latestExpiration === undefined
    ? { targetTier: "free", expiresAt: null }
    : {
      targetTier: "pro",
      expiresAt: new Date(latestExpiration).toISOString(),
    };
}

/**
 * Returns whether the authoritative snapshot contains an active detached
 * seven-day pass backed by an App Store transaction. This is deliberately
 * narrower than durable policy: historical destination records cannot grant
 * themselves permission to participate in entitlement projection.
 */
export function hasActiveRevenueCatAppStorePass(
  customerInfo: RevenueCatCustomerInfo,
  event?: RevenueCatWebhookEvent,
): boolean {
  return activePassExpiration(
    customerInfo.subscriber,
    customerInfo.requestDateMs,
    event,
    true,
  ) !== null;
}

/**
 * Returns an explicit durable-policy update for detached seven-day pass
 * history. CustomerInfo retains non-subscription transactions after refunds,
 * so background reconciliation may infer that history only after a signed
 * purchase signal and must disable it on revocation or a transfer source.
 * A transfer destination is authorized separately from the resolved source's
 * durable policy; destination history alone is never authority. Unrelated
 * events preserve the previously recorded policy.
 */
export function revenueCatNonSubscriptionPassGrantDecision(
  customerInfo: RevenueCatCustomerInfo,
  event: RevenueCatWebhookEvent,
  subjectKind: "customer" | "transfer_source" | "transfer_destination",
): boolean | null {
  if (event.type === "TRANSFER") {
    if (subjectKind === "transfer_source") return false;
    if (subjectKind === "transfer_destination") return null;
    return null;
  }
  if (!isSevenDayPassProduct(event.productId)) return null;
  if (PASS_REVOCATION_EVENTS.has(event.type)) {
    // A refund may target an older transaction while a later pass remains
    // valid. Persist permission only when the event-aware parser can still
    // prove another active App Store transaction.
    return activePassExpiration(
      customerInfo.subscriber,
      customerInfo.requestDateMs,
      event,
      true,
    ) !== null;
  }
  if (PASS_PURCHASE_EVENTS.has(event.type)) {
    // A signed purchase signal without matching authoritative CustomerInfo can
    // be a provider propagation race. Retrying is safer than permanently
    // enabling historical transaction inference or dropping paid access.
    if (
      activePassExpiration(
        customerInfo.subscriber,
        customerInfo.requestDateMs,
        event,
        true,
      ) === null
    ) {
      throw new RevenueCatApiError(
        "RevenueCat CustomerInfo did not include the purchased pass.",
        true,
      );
    }
    return true;
  }
  return null;
}

/**
 * Derives only active access issued through RevenueCat's promotional store.
 * This state is imported into the private account-grant ledger and must never
 * follow the stable purchase principal across sign-out or account switching.
 * Unknown and missing provenance fail closed.
 */
export function deriveRevenueCatAccountGrantState(
  customerInfo: RevenueCatCustomerInfo,
): RevenueCatEntitlementState {
  const subscriptions = isRecord(customerInfo.subscriber.subscriptions)
    ? customerInfo.subscriber.subscriptions
    : {};
  const entitlements = customerInfo.subscriber.entitlements;
  let latestExpiration: number | undefined;

  if (isRecord(entitlements)) {
    for (const [entitlementId, entitlement] of Object.entries(entitlements)) {
      if (!PAID_ENTITLEMENT_IDS.has(entitlementId) || !isRecord(entitlement)) {
        continue;
      }
      const productIdentifier = entitlement.product_identifier;
      const subscription = typeof productIdentifier === "string"
        ? subscriptions[productIdentifier]
        : undefined;
      if (!isPromotionalPurchaseRecord(subscription)) continue;

      const expiration = activeEntitlementExpiration(
        entitlement,
        customerInfo.requestDateMs,
      );
      if (expiration === null) {
        return { targetTier: "pro", expiresAt: null };
      }
      if (
        expiration !== undefined &&
        (latestExpiration === undefined || expiration > latestExpiration)
      ) {
        latestExpiration = expiration;
      }
    }
  }

  return latestExpiration === undefined
    ? { targetTier: "free", expiresAt: null }
    : {
      targetTier: "pro",
      expiresAt: new Date(latestExpiration).toISOString(),
    };
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

    return await readRevenueCatCustomerInfoResponse(response);
  } catch (error) {
    if (error instanceof RevenueCatApiError) throw error;
    const detail = error instanceof Error ? error.message : "response failure";
    throw new RevenueCatApiError(
      `RevenueCat CustomerInfo response failed: ${detail}`,
      true,
    );
  }
}
