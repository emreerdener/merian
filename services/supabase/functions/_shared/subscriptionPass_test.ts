import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  isSevenDayPassProduct,
  passExpirationFromRevenueCatEvent,
  SEVEN_DAY_PASS_DURATION_MS,
  SEVEN_DAY_PASS_PRODUCT_ID,
} from "./subscriptionPass.ts";

Deno.test("isSevenDayPassProduct: accepts only the exact product id", () => {
  assertEquals(isSevenDayPassProduct(SEVEN_DAY_PASS_PRODUCT_ID), true);
  assertEquals(isSevenDayPassProduct("merian_7day_pass"), false);
  assertEquals(isSevenDayPassProduct("merian_7_day_pass_bonus"), false);
  assertEquals(isSevenDayPassProduct("MERIAN_7_DAY_PASS"), false);
  assertEquals(isSevenDayPassProduct(null), false);
});

Deno.test("passExpirationFromRevenueCatEvent: uses purchased_at_ms plus exactly 7 UTC days", () => {
  const purchasedAtMs = Date.parse("2026-06-16T09:30:00.000Z");

  assertEquals(
    passExpirationFromRevenueCatEvent({
      product_id: SEVEN_DAY_PASS_PRODUCT_ID,
      purchased_at_ms: purchasedAtMs,
    }),
    new Date(purchasedAtMs + SEVEN_DAY_PASS_DURATION_MS).toISOString(),
  );
});

Deno.test("passExpirationFromRevenueCatEvent: rejects unknown products", () => {
  assertThrows(
    () =>
      passExpirationFromRevenueCatEvent({
        product_id: "not_the_pass",
        purchased_at_ms: Date.now(),
      }),
    Error,
    "unknown product",
  );
});

Deno.test("passExpirationFromRevenueCatEvent: rejects missing and invalid purchase timestamps", () => {
  assertThrows(
    () =>
      passExpirationFromRevenueCatEvent({
        product_id: SEVEN_DAY_PASS_PRODUCT_ID,
      }),
    Error,
    "missing purchased_at_ms",
  );

  assertThrows(
    () =>
      passExpirationFromRevenueCatEvent({
        product_id: SEVEN_DAY_PASS_PRODUCT_ID,
        purchased_at_ms: Number.NaN,
      }),
    Error,
    "invalid purchased_at_ms",
  );
});
