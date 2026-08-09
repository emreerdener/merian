import { fetchWithDeadline } from "../_shared/outbound.ts";
import {
  deriveRevenueCatEntitlementState,
  fetchRevenueCatCustomerInfo,
  readRevenueCatCustomerInfoResponse,
  RevenueCatApiError,
  type RevenueCatCustomerInfo,
  type RevenueCatEntitlementState,
} from "../revenuecat-webhook/subscriber.ts";

const REVENUECAT_API_BASE_URL = "https://api.revenuecat.com/v1";
const REVENUECAT_REQUEST_TIMEOUT_MS = 10_000;
const PRO_ENTITLEMENT_ID = "pro";
const CANONICAL_UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type RevenueCatGhostMergeAccessStatus =
  | "source_free"
  | "target_already_covers"
  | "granted";

export type RevenueCatGhostMergeAccessResult =
  | {
    succeeded: true;
    status: RevenueCatGhostMergeAccessStatus;
  }
  | {
    succeeded: false;
    errorCode: string;
  };

export class RevenueCatGhostMergeError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
    this.name = "RevenueCatGhostMergeError";
  }
}

/**
 * RevenueCat App User IDs are case-sensitive. Database UUIDs are emitted in
 * lowercase by Postgres, while Merian's only provider identity is uppercase.
 */
export function canonicalRevenueCatAppUserID(value: string): string {
  const normalized = value.trim();
  if (!CANONICAL_UUID_PATTERN.test(normalized)) {
    throw new RevenueCatGhostMergeError(
      "revenuecat_invalid_app_user_id",
      "Ghost merge contained an invalid RevenueCat App User ID.",
    );
  }
  return normalized.toUpperCase();
}

export async function preserveRevenueCatAccessForGhostMerge(
  ghostUserID: string,
  targetUserID: string,
  apiKey: string,
  fetcher: typeof fetch = fetch,
): Promise<RevenueCatGhostMergeAccessResult> {
  if (!apiKey.startsWith("sk_")) {
    return {
      succeeded: false,
      errorCode: apiKey.length === 0
        ? "revenuecat_secret_missing"
        : "revenuecat_secret_invalid",
    };
  }

  try {
    const status = await transferRevenueCatAccessForGhostMerge(
      ghostUserID,
      targetUserID,
      apiKey,
      fetcher,
    );
    return { succeeded: true, status };
  } catch (error) {
    if (error instanceof RevenueCatGhostMergeError) {
      return { succeeded: false, errorCode: error.code };
    }
    if (error instanceof RevenueCatApiError) {
      return {
        succeeded: false,
        errorCode: error.retryable
          ? "revenuecat_customer_info_retryable"
          : "revenuecat_customer_info_rejected",
      };
    }
    return { succeeded: false, errorCode: "revenuecat_handoff_failed" };
  }
}

/**
 * Mirrors only the active functional Pro horizon. It never revokes the source
 * customer or attempts to synthesize a store receipt. The iOS client performs
 * `syncPurchases()` after the durable server handoff so RevenueCat's configured
 * transfer behavior can move the real App Store receipt as well.
 */
export async function transferRevenueCatAccessForGhostMerge(
  ghostUserID: string,
  targetUserID: string,
  apiKey: string,
  fetcher: typeof fetch = fetch,
): Promise<RevenueCatGhostMergeAccessStatus> {
  const sourceAppUserID = canonicalRevenueCatAppUserID(ghostUserID);
  const targetAppUserID = canonicalRevenueCatAppUserID(targetUserID);
  if (sourceAppUserID === targetAppUserID) {
    return "target_already_covers";
  }

  const sourceInfo = await fetchRevenueCatCustomerInfo(
    sourceAppUserID,
    apiKey,
    fetcher,
  );
  const sourceAccess = deriveRevenueCatEntitlementState(sourceInfo);
  if (sourceAccess.targetTier === "free") return "source_free";

  const targetInfo = await fetchRevenueCatCustomerInfo(
    targetAppUserID,
    apiKey,
    fetcher,
  );
  const targetAccess = deriveRevenueCatEntitlementState(targetInfo);
  if (accessCovers(targetAccess, sourceAccess)) {
    return "target_already_covers";
  }

  const grantedInfo = await grantMatchingProHorizon({
    targetAppUserID,
    sourceAccess,
    apiKey,
    fetcher,
  });
  const grantedAccess = deriveRevenueCatEntitlementState(grantedInfo);
  if (!accessCovers(grantedAccess, sourceAccess)) {
    throw new RevenueCatGhostMergeError(
      "revenuecat_grant_not_preserved",
      "RevenueCat did not confirm the Ghost account's Pro horizon on the target.",
    );
  }
  return "granted";
}

function accessCovers(
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

async function grantMatchingProHorizon(input: {
  targetAppUserID: string;
  sourceAccess: RevenueCatEntitlementState;
  apiKey: string;
  fetcher: typeof fetch;
}): Promise<RevenueCatCustomerInfo> {
  const endTimeMs = input.sourceAccess.expiresAt === null
    ? null
    : Date.parse(input.sourceAccess.expiresAt);
  if (
    endTimeMs !== null &&
    (!Number.isSafeInteger(endTimeMs) || endTimeMs <= 0)
  ) {
    throw new RevenueCatGhostMergeError(
      "revenuecat_invalid_source_horizon",
      "RevenueCat returned an invalid active entitlement horizon.",
    );
  }
  const body = endTimeMs === null
    ? { duration: "lifetime" }
    : { end_time_ms: endTimeMs };

  let response: Response;
  try {
    response = await fetchWithDeadline(
      `${REVENUECAT_API_BASE_URL}/subscribers/${
        encodeURIComponent(input.targetAppUserID)
      }/entitlements/${PRO_ENTITLEMENT_ID}/promotional`,
      {
        method: "POST",
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${input.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      },
      {
        fetcher: input.fetcher,
        timeoutMs: REVENUECAT_REQUEST_TIMEOUT_MS,
      },
    );
  } catch (error) {
    const detail = error instanceof Error ? error.message : "network failure";
    throw new RevenueCatApiError(
      `RevenueCat promotional grant failed: ${detail}`,
      true,
    );
  }

  if (response.status !== 201) {
    const retryable = response.status === 408 || response.status === 425 ||
      response.status === 429 || response.status >= 500;
    await response.body?.cancel().catch(() => undefined);
    throw new RevenueCatApiError(
      `RevenueCat promotional grant returned HTTP ${response.status}.`,
      retryable,
    );
  }
  return await readRevenueCatCustomerInfoResponse(response);
}
