export const SEVEN_DAY_PASS_PRODUCT_ID = "merian_7_day_pass";
export const SEVEN_DAY_PASS_DURATION_MS = 7 * 24 * 60 * 60 * 1000;

export interface RevenueCatPassEvent {
  product_id?: unknown;
  purchased_at_ms?: unknown;
}

export function isSevenDayPassProduct(productId: unknown): boolean {
  return productId === SEVEN_DAY_PASS_PRODUCT_ID;
}

export function passExpirationFromRevenueCatEvent(
  event: RevenueCatPassEvent,
): string {
  if (!isSevenDayPassProduct(event.product_id)) {
    throw new Error(
      "Cannot compute 7-day pass expiration for unknown product.",
    );
  }

  if (typeof event.purchased_at_ms !== "number") {
    throw new Error("7-day pass purchase is missing purchased_at_ms.");
  }

  const purchasedAt = new Date(event.purchased_at_ms);
  const purchasedAtMs = purchasedAt.getTime();
  if (!Number.isFinite(purchasedAtMs)) {
    throw new Error("7-day pass purchase has invalid purchased_at_ms.");
  }

  return new Date(purchasedAtMs + SEVEN_DAY_PASS_DURATION_MS).toISOString();
}
