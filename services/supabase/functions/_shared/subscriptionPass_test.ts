import { assertEquals } from "@std/assert";
import {
  isSevenDayPassProduct,
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

Deno.test("seven-day pass duration is exactly seven UTC days", () => {
  assertEquals(SEVEN_DAY_PASS_DURATION_MS, 7 * 24 * 60 * 60 * 1000);
});
