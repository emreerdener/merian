import { assertEquals } from "@std/assert";
import {
  parseResolvePurchasePrincipalRequest,
  PURCHASE_PRINCIPAL_CLIENT_PROTOCOL,
  sha256Hex,
} from "./protocol.ts";

const CAPABILITY = "A".repeat(43);
const ROTATION_ID = "550e8400-e29b-41d4-a716-446655440000";
const ROTATION_SECRET = "B".repeat(43);

Deno.test("purchase principal protocol accepts compatible resolve and exact v3 rotation bodies", () => {
  assertEquals(PURCHASE_PRINCIPAL_CLIENT_PROTOCOL, 3);
  for (const clientProtocol of [1, PURCHASE_PRINCIPAL_CLIENT_PROTOCOL]) {
    assertEquals(
      parseResolvePurchasePrincipalRequest({
        operation: "resolve",
        installation_capability: CAPABILITY,
        client_protocol: clientProtocol,
        binding_intent_generation: 7,
      }),
      {
        operation: "resolve",
        installationCapability: CAPABILITY,
        clientProtocol,
        bindingIntentGeneration: 7,
      },
    );
  }

  assertEquals(
    parseResolvePurchasePrincipalRequest({
      operation: "prepare_signout_rotation",
      installation_capability: CAPABILITY,
      client_protocol: PURCHASE_PRINCIPAL_CLIENT_PROTOCOL,
      rotation_id: ROTATION_ID,
      rotation_secret: ROTATION_SECRET,
      expected_binding_generation: 4,
    }),
    {
      operation: "prepare_signout_rotation",
      installationCapability: CAPABILITY,
      clientProtocol: 3,
      rotationId: ROTATION_ID,
      rotationSecret: ROTATION_SECRET,
      expectedBindingGeneration: 4,
    },
  );
  for (
    const operation of [
      "claim_signout_rotation",
      "cancel_signout_rotation",
    ] as const
  ) {
    assertEquals(
      parseResolvePurchasePrincipalRequest({
        operation,
        installation_capability: CAPABILITY,
        client_protocol: PURCHASE_PRINCIPAL_CLIENT_PROTOCOL,
        rotation_id: ROTATION_ID,
        rotation_secret: ROTATION_SECRET,
      }),
      {
        operation,
        installationCapability: CAPABILITY,
        clientProtocol: 3,
        rotationId: ROTATION_ID,
        rotationSecret: ROTATION_SECRET,
      },
    );
  }

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
        operation: "claim_signout_rotation",
        installation_capability: CAPABILITY,
        client_protocol: 3,
        rotation_id: ROTATION_ID,
        rotation_secret: ROTATION_SECRET,
        destination_user_id: "caller-selected",
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
      {
        operation: "prepare_signout_rotation",
        installation_capability: CAPABILITY,
        client_protocol: 2,
        rotation_id: ROTATION_ID,
        rotation_secret: ROTATION_SECRET,
        expected_binding_generation: 4,
      },
      {
        operation: "prepare_signout_rotation",
        installation_capability: CAPABILITY,
        client_protocol: 3,
        rotation_id: "not-a-uuid",
        rotation_secret: ROTATION_SECRET,
        expected_binding_generation: 4,
      },
      {
        operation: "claim_signout_rotation",
        installation_capability: CAPABILITY,
        client_protocol: 3,
        rotation_id: ROTATION_ID,
        rotation_secret: "short",
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
