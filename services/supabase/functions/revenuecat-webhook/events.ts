import {
  isSevenDayPassProduct,
  passExpirationFromRevenueCatEvent,
} from "../_shared/subscriptionPass.ts";

export interface RevenueCatWebhookEvent {
  type?: unknown;
  product_id?: unknown;
  purchased_at_ms?: unknown;
}

export interface TierUpdateAction {
  targetTier: "pro" | "free";
  expiresAt: string | null;
  storageMigration: "free_to_pro" | "pro_to_free";
}

export function classifyRevenueCatEvent(
  event: RevenueCatWebhookEvent,
): TierUpdateAction | null {
  const eventType = event.type;
  const isSevenDayPass = isSevenDayPassProduct(event.product_id);

  if (isSevenDayPass && eventType === "NON_RENEWING_PURCHASE") {
    return {
      targetTier: "pro",
      expiresAt: passExpirationFromRevenueCatEvent(event),
      storageMigration: "free_to_pro",
    };
  }

  if (
    isSevenDayPass &&
    ["CANCELLATION", "EXPIRATION", "REFUND"].includes(String(eventType))
  ) {
    return {
      targetTier: "free",
      expiresAt: null,
      storageMigration: "pro_to_free",
    };
  }

  if (
    ["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION"].includes(
      String(eventType),
    )
  ) {
    return {
      targetTier: "pro",
      expiresAt: null,
      storageMigration: "free_to_pro",
    };
  }

  if (eventType === "EXPIRATION") {
    return {
      targetTier: "free",
      expiresAt: null,
      storageMigration: "pro_to_free",
    };
  }

  return null;
}
