import { assertEquals } from "@std/assert";
import {
  hashAccountDeletionCapability,
  parseAccountDeletionRecoveryRequest,
  parseSafeDeleteRequest,
  sha256Hex,
} from "./protocol.ts";

const CAPABILITY = "A".repeat(43);
const ACKNOWLEDGEMENT_CAPABILITY = "B".repeat(43);

Deno.test("safe-delete protocol preserves empty legacy bodies and exact capabilities", () => {
  assertEquals(parseSafeDeleteRequest({}), {
    protocolVersion: 1,
    operation: "commit",
    recoveryCapability: null,
  });
  assertEquals(
    parseSafeDeleteRequest({ recovery_capability: CAPABILITY }),
    {
      protocolVersion: 1,
      operation: "commit",
      recoveryCapability: CAPABILITY,
    },
  );
  assertEquals(
    parseSafeDeleteRequest({
      protocol_version: 2,
      operation: "prepare",
      recovery_capability: CAPABILITY,
      acknowledgement_capability: ACKNOWLEDGEMENT_CAPABILITY,
    }),
    {
      protocolVersion: 2,
      operation: "prepare",
      recoveryCapability: CAPABILITY,
      acknowledgementCapability: ACKNOWLEDGEMENT_CAPABILITY,
    },
  );
  assertEquals(
    parseSafeDeleteRequest({
      protocol_version: 2,
      operation: "commit",
      recovery_capability: CAPABILITY,
    }),
    {
      protocolVersion: 2,
      operation: "commit",
      recoveryCapability: CAPABILITY,
    },
  );

  for (
    const body of [
      null,
      [],
      { recovery_capability: "short" },
      { recovery_capability: CAPABILITY, user_id: crypto.randomUUID() },
      { capability: CAPABILITY },
      {
        protocol_version: 2,
        operation: "prepare",
        recovery_capability: CAPABILITY,
        acknowledgement_capability: CAPABILITY,
      },
    ]
  ) {
    assertEquals("status" in parseSafeDeleteRequest(body), true);
  }
});

Deno.test("account-deletion recovery accepts only exact recover or acknowledge bodies", () => {
  for (const operation of ["recover", "acknowledge"] as const) {
    assertEquals(
      parseAccountDeletionRecoveryRequest({
        operation,
        recovery_capability: CAPABILITY,
      }),
      {
        protocolVersion: 1,
        operation,
        capability: CAPABILITY,
      },
    );
  }

  assertEquals(
    parseAccountDeletionRecoveryRequest({
      protocol_version: 2,
      operation: "recover",
      recovery_capability: CAPABILITY,
    }),
    {
      protocolVersion: 2,
      operation: "recover",
      capability: CAPABILITY,
    },
  );
  assertEquals(
    parseAccountDeletionRecoveryRequest({
      protocol_version: 2,
      operation: "acknowledge",
      acknowledgement_capability: ACKNOWLEDGEMENT_CAPABILITY,
    }),
    {
      protocolVersion: 2,
      operation: "acknowledge",
      capability: ACKNOWLEDGEMENT_CAPABILITY,
    },
  );

  for (
    const body of [
      {},
      { operation: "delete", recovery_capability: CAPABILITY },
      { operation: "recover", recovery_capability: "short" },
      {
        operation: "recover",
        recovery_capability: CAPABILITY,
        user_id: crypto.randomUUID(),
      },
    ]
  ) {
    assertEquals(
      "status" in parseAccountDeletionRecoveryRequest(body),
      true,
    );
  }
});

Deno.test("account-deletion recovery capability hashes deterministically", async () => {
  assertEquals(
    await sha256Hex(CAPABILITY),
    "0f007385b6f9d4b7eeb2748605afe1a984a0a3bfa3f014d09e2a784ce9e5cd1a",
  );
  assertEquals(
    await hashAccountDeletionCapability(CAPABILITY, "v2_recovery"),
    "645e4eada850b504783b4735ad1260bd60c61e4ed7f245075a463a2c7e651c58",
  );
  assertEquals(
    await hashAccountDeletionCapability(CAPABILITY, "v2_acknowledgement"),
    "647623a2ed61d3b776ed90aea5eae2b9f5ec1fc8ff00af18a53bd9ded6e4ed26",
  );
});
