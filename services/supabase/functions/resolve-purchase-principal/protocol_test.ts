import { assertEquals } from "@std/assert";
import { parseResolvePurchasePrincipalRequest, sha256Hex } from "./protocol.ts";

const CAPABILITY = "A".repeat(43);

Deno.test("purchase principal protocol accepts only its exact v1 body", () => {
  assertEquals(
    parseResolvePurchasePrincipalRequest({
      operation: "resolve",
      installation_capability: CAPABILITY,
      client_protocol: 1,
      binding_intent_generation: 7,
    }),
    {
      operation: "resolve",
      installationCapability: CAPABILITY,
      clientProtocol: 1,
      bindingIntentGeneration: 7,
    },
  );

  for (
    const body of [
      null,
      {},
      {
        operation: "resolve",
        installation_capability: CAPABILITY,
        client_protocol: 1,
        binding_intent_generation: 7,
        purchase_principal_id: "caller-selected",
      },
      {
        operation: "claim",
        installation_capability: CAPABILITY,
        client_protocol: 1,
        binding_intent_generation: 7,
      },
      {
        operation: "resolve",
        installation_capability: "short",
        client_protocol: 1,
        binding_intent_generation: 7,
      },
      {
        operation: "resolve",
        installation_capability: CAPABILITY,
        client_protocol: 1.5,
        binding_intent_generation: 7,
      },
      {
        operation: "resolve",
        installation_capability: CAPABILITY,
        client_protocol: 1,
        binding_intent_generation: 0,
      },
      {
        operation: "resolve",
        installation_capability: CAPABILITY,
        client_protocol: 1,
        binding_intent_generation: Number.MAX_SAFE_INTEGER + 1,
      },
    ]
  ) {
    assertEquals("status" in parseResolvePurchasePrincipalRequest(body), true);
  }
});

Deno.test("purchase principal capability hashing is deterministic", async () => {
  assertEquals(
    await sha256Hex(CAPABILITY),
    "0f007385b6f9d4b7eeb2748605afe1a984a0a3bfa3f014d09e2a784ce9e5cd1a",
  );
});
