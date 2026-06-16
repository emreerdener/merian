import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { SEVEN_DAY_PASS_PRODUCT_ID } from "../_shared/subscriptionPass.ts";
import { classifyRevenueCatEvent } from "./events.ts";

Deno.test("classifyRevenueCatEvent: exact pass purchase grants timed pro from RevenueCat purchase time", () => {
  const action = classifyRevenueCatEvent({
    type: "NON_RENEWING_PURCHASE",
    product_id: SEVEN_DAY_PASS_PRODUCT_ID,
    purchased_at_ms: Date.parse("2026-06-16T00:00:00.000Z"),
  });

  assertEquals(action, {
    targetTier: "pro",
    expiresAt: "2026-06-23T00:00:00.000Z",
    storageMigration: "free_to_pro",
  });
});

Deno.test("classifyRevenueCatEvent: unrelated non-renewing purchase is ignored", () => {
  assertEquals(
    classifyRevenueCatEvent({
      type: "NON_RENEWING_PURCHASE",
      product_id: "merian_tip_499",
      purchased_at_ms: Date.parse("2026-06-16T00:00:00.000Z"),
    }),
    null,
  );
});

Deno.test("classifyRevenueCatEvent: substring-like pass identifiers do not grant access", () => {
  assertEquals(
    classifyRevenueCatEvent({
      type: "NON_RENEWING_PURCHASE",
      product_id: `${SEVEN_DAY_PASS_PRODUCT_ID}_extra`,
      purchased_at_ms: Date.parse("2026-06-16T00:00:00.000Z"),
    }),
    null,
  );
});

Deno.test("classifyRevenueCatEvent: normal subscription purchases clear timed expiry", () => {
  for (const type of ["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION"]) {
    assertEquals(classifyRevenueCatEvent({ type, product_id: "merian_pro" }), {
      targetTier: "pro",
      expiresAt: null,
      storageMigration: "free_to_pro",
    });
  }
});

Deno.test("classifyRevenueCatEvent: standard expiration downgrades with no timed expiry", () => {
  assertEquals(
    classifyRevenueCatEvent({
      type: "EXPIRATION",
      product_id: "merian_pro_monthly",
    }),
    {
      targetTier: "free",
      expiresAt: null,
      storageMigration: "pro_to_free",
    },
  );
});

Deno.test("classifyRevenueCatEvent: pass cancellation/refund/expiration immediately downgrades", () => {
  for (const type of ["CANCELLATION", "EXPIRATION", "REFUND"]) {
    assertEquals(
      classifyRevenueCatEvent({
        type,
        product_id: SEVEN_DAY_PASS_PRODUCT_ID,
      }),
      {
        targetTier: "free",
        expiresAt: null,
        storageMigration: "pro_to_free",
      },
    );
  }
});

Deno.test("classifyRevenueCatEvent: non-tier RevenueCat event is ignored", () => {
  assertEquals(
    classifyRevenueCatEvent({
      type: "BILLING_ISSUE",
      product_id: "merian_pro_monthly",
    }),
    null,
  );
});
