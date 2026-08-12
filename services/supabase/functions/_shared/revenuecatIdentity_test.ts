import { assertEquals, assertThrows } from "@std/assert";
import {
  canonicalRevenueCatAppUserID,
  RevenueCatIdentityError,
} from "./revenuecatIdentity.ts";

Deno.test("canonical RevenueCat identity uppercases UUIDs and rejects anonymous IDs", () => {
  assertEquals(
    canonicalRevenueCatAppUserID("d5f4357e-11d5-4c6c-8669-c151a0ec297f"),
    "D5F4357E-11D5-4C6C-8669-C151A0EC297F",
  );
  assertThrows(
    () => canonicalRevenueCatAppUserID("$RCAnonymousID:x"),
    RevenueCatIdentityError,
  );
});
