import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  ENTITLEMENT_PROTOCOL_HEADER,
  entitlementProtocolResponse,
  getTierForUser,
  resolutionForEntitlementRow,
  resolveTierForUser,
} from "./entitlement.ts";

const complimentaryRow = {
  current_plan: "pro_complimentary",
  current_tier: "pro",
  is_paid: false,
  scans_remaining: 3,
  scans_available_to_start: 2,
  in_flight_count: 1,
  entitlement_version: 8,
};

function mockSupabase(
  responses: Array<{
    data: Record<string, unknown> | null;
    error?: { message: string } | null;
  }>,
) {
  let callCount = 0;
  return {
    get callCount() {
      return callCount;
    },
    rpc(name: string, arguments_: Record<string, unknown>) {
      assertEquals(name, "get_user_entitlement_service");
      assertEquals(typeof arguments_.p_user_id, "string");
      return {
        abortSignal() {
          const response = responses[Math.min(callCount, responses.length - 1)];
          callCount += 1;
          return Promise.resolve({
            data: response.data,
            error: response.error ?? null,
          });
        },
      };
    },
  };
}

Deno.test("complimentary entitlement is server-derived and fully functional Pro", () => {
  assertEquals(resolutionForEntitlementRow(complimentaryRow), {
    ...complimentaryRow,
    effective_tier: "pro",
    plan: "pro_complimentary",
    subscription_tier: "free",
    trial_active: false,
    user_exists: true,
  });
});

Deno.test("paid precedence and historical trial rows remain readable", () => {
  const paid = resolutionForEntitlementRow({
    ...complimentaryRow,
    current_plan: "pro_paid",
    is_paid: true,
  });
  assertEquals(paid.plan, "pro_paid");
  assertEquals(paid.subscription_tier, "pro");

  const historical = resolutionForEntitlementRow({
    ...complimentaryRow,
    current_plan: "pro_trial",
    scans_remaining: 0,
    scans_available_to_start: 0,
    in_flight_count: 0,
  });
  assertEquals(historical.trial_active, true);
});

Deno.test("free exhaustion resolves without functional Pro", () => {
  const resolution = resolutionForEntitlementRow({
    current_plan: "free",
    current_tier: "free",
    is_paid: false,
    scans_remaining: 0,
    scans_available_to_start: 0,
    in_flight_count: 0,
    entitlement_version: 12,
  });
  assertEquals(resolution.effective_tier, "free");
  assertEquals(resolution.plan, "free");
});

Deno.test("malformed entitlement snapshots fail closed", () => {
  for (
    const row of [
      { ...complimentaryRow, current_plan: "unexpected" },
      { ...complimentaryRow, scans_remaining: 4 },
      { ...complimentaryRow, scans_remaining: 1, scans_available_to_start: 2 },
      { ...complimentaryRow, scans_available_to_start: 1 },
      { ...complimentaryRow, entitlement_version: 0 },
      { ...complimentaryRow, is_paid: true },
    ]
  ) {
    const error = assertThrows(
      () => resolutionForEntitlementRow(row),
      Error,
      "AI entitlement could not be verified",
    ) as Error & { status?: number; code?: string };
    assertEquals(error.status, 503);
    assertEquals(error.code, "ai_entitlement_unavailable");
  }
});

Deno.test("database and transport entitlement failures fail closed", async () => {
  const databaseClient = mockSupabase([{
    data: null,
    error: { message: "database unavailable" },
  }]);
  await assertRejects(
    () => resolveTierForUser(crypto.randomUUID(), databaseClient as never),
    Error,
    "AI entitlement could not be verified",
  );

  const transportClient = {
    rpc: () => ({
      abortSignal: () => Promise.reject(new DOMException("timeout")),
    }),
  };
  await assertRejects(
    () => resolveTierForUser(crypto.randomUUID(), transportClient as never),
    Error,
    "AI entitlement could not be verified",
  );
});

Deno.test("entitlement resolution always reads the database", async () => {
  const client = mockSupabase([
    { data: complimentaryRow },
    {
      data: {
        current_plan: "free",
        current_tier: "free",
        is_paid: false,
        scans_remaining: 0,
        scans_available_to_start: 0,
        in_flight_count: 0,
        entitlement_version: 9,
      },
    },
  ]);
  const userId = crypto.randomUUID();
  assertEquals(await getTierForUser(userId, client as never), "pro");
  assertEquals(await getTierForUser(userId, client as never), "free");
  assertEquals(client.callCount, 2);
});

Deno.test("all public Identify requests require protocol 2 after cutover", async () => {
  const postCutoverClient = {
    rpc(name: string) {
      assertEquals(name, "get_entitlement_rollout_service");
      return {
        abortSignal: () =>
          Promise.resolve({
            data: {
              entitlement_mode: "complimentary",
              required_client_protocol: 2,
              mode_version: 2,
            },
            error: null,
          }),
      };
    },
  };
  for (const value of [null, "1", "3", "invalid"]) {
    const headers = new Headers();
    if (value) headers.set(ENTITLEMENT_PROTOCOL_HEADER, value);
    const response = await entitlementProtocolResponse(
      new Request("https://example.invalid", { headers }),
      postCutoverClient as never,
    );
    assertEquals(response?.status, 426);
    assertEquals((await response?.json()).code, "client_update_required");
  }

  const current = new Request("https://example.invalid", {
    headers: { [ENTITLEMENT_PROTOCOL_HEADER]: "2" },
  });
  assertEquals(
    await entitlementProtocolResponse(current, postCutoverClient as never),
    null,
  );
});

Deno.test("schema-first legacy rollout accepts clients before cutover", async () => {
  const legacyClient = {
    rpc: () => ({
      abortSignal: () =>
        Promise.resolve({
          data: {
            entitlement_mode: "legacy_trial",
            required_client_protocol: 0,
            mode_version: 1,
          },
          error: null,
        }),
    }),
  };
  assertEquals(
    await entitlementProtocolResponse(
      new Request("https://example.invalid"),
      legacyClient as never,
    ),
    null,
  );
});
