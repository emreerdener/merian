import { assertEquals, assertMatch } from "@std/assert";
import {
  generateHandoffSecret,
  parseSignoutPurchaseHandoffRequest,
  sha256Hex,
} from "./protocol.ts";

const HANDOFF_ID = "550e8400-e29b-41d4-a716-446655440000";
const HANDOFF_SECRET = "A".repeat(43);

Deno.test("sign-out purchase protocol accepts only exact operation bodies", () => {
  assertEquals(parseSignoutPurchaseHandoffRequest({ operation: "prepare" }), {
    operation: "prepare",
  });
  assertEquals(
    parseSignoutPurchaseHandoffRequest({
      operation: "bind",
      handoff_id: HANDOFF_ID.toUpperCase(),
      handoff_secret: HANDOFF_SECRET,
    }),
    {
      operation: "bind",
      handoffId: HANDOFF_ID,
      handoffSecret: HANDOFF_SECRET,
    },
  );
  assertEquals(
    parseSignoutPurchaseHandoffRequest({
      operation: "cancel",
      handoff_id: HANDOFF_ID,
      handoff_secret: HANDOFF_SECRET,
    }),
    {
      operation: "cancel",
      handoffId: HANDOFF_ID,
      handoffSecret: HANDOFF_SECRET,
    },
  );

  for (
    const body of [
      { operation: "prepare", destination_user_id: HANDOFF_ID },
      { operation: "complete", handoff_id: HANDOFF_ID },
      {
        operation: "bind",
        handoff_id: HANDOFF_ID,
        handoff_secret: "short",
      },
      {
        operation: "complete",
        handoff_id: "$RCAnonymousID:unsafe",
        handoff_secret: HANDOFF_SECRET,
      },
    ]
  ) {
    const result = parseSignoutPurchaseHandoffRequest(body);
    assertEquals("status" in result, true);
  }
});

Deno.test("sign-out purchase proof is 256-bit base64url and hashes deterministically", async () => {
  const first = generateHandoffSecret();
  const second = generateHandoffSecret();
  assertMatch(first, /^[A-Za-z0-9_-]{43}$/);
  assertMatch(second, /^[A-Za-z0-9_-]{43}$/);
  assertEquals(first === second, false);
  assertEquals(
    await sha256Hex(HANDOFF_SECRET),
    "0f007385b6f9d4b7eeb2748605afe1a984a0a3bfa3f014d09e2a784ce9e5cd1a",
  );
});
