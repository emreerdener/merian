import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  getTierForUser,
  resolutionForUserRow,
  resolveTierForUser,
} from "./entitlement.ts";

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
    from: () => ({
      select: () => ({
        eq: () => ({
          abortSignal: () => ({
            maybeSingle: () => {
              const response =
                responses[Math.min(callCount, responses.length - 1)];
              callCount += 1;
              return Promise.resolve({
                data: response.data,
                error: response.error ?? null,
              });
            },
          }),
        }),
      }),
    }),
  };
}

function isoDaysAgo(days: number): string {
  return new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
}

function isoDaysFromNow(days: number): string {
  return new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
}

Deno.test("paid and timed Pro rows resolve from durable entitlement state", () => {
  assertEquals(
    resolutionForUserRow({
      subscription_tier: "pro",
      created_at: isoDaysAgo(20),
      entitlement_version: 7,
    }),
    {
      effective_tier: "pro",
      plan: "pro_paid",
      subscription_tier: "pro",
      trial_active: false,
      user_exists: true,
      entitlement_version: 7,
    },
  );
  assertEquals(
    resolutionForUserRow({
      subscription_tier: "pro",
      created_at: isoDaysAgo(20),
      subscription_expires_at: isoDaysFromNow(1),
      entitlement_version: 3,
    }).effective_tier,
    "pro",
  );
});

Deno.test("an expired timed Pro pass resolves free", () => {
  const resolution = resolutionForUserRow({
    subscription_tier: "pro",
    created_at: isoDaysAgo(20),
    subscription_expires_at: isoDaysAgo(1),
    entitlement_version: 4,
  });
  assertEquals(resolution.effective_tier, "free");
  assertEquals(resolution.plan, "free");
  assertEquals(resolution.subscription_tier, "free");
  assertEquals(resolution.entitlement_version, 4);
});

Deno.test("recent free users receive the explicit seven-day trial", () => {
  const resolution = resolutionForUserRow({
    subscription_tier: "free",
    created_at: isoDaysAgo(2),
    entitlement_version: 2,
  });
  assertEquals(resolution.effective_tier, "pro");
  assertEquals(resolution.plan, "pro_trial");
  assertEquals(resolution.trial_active, true);
});

Deno.test("free users outside the trial resolve free", () => {
  const resolution = resolutionForUserRow({
    subscription_tier: "free",
    created_at: isoDaysAgo(8),
    entitlement_version: 9,
  });
  assertEquals(resolution.effective_tier, "free");
  assertEquals(resolution.plan, "free");
  assertEquals(resolution.trial_active, false);
});

Deno.test("future-dated free profiles do not receive an extended trial", () => {
  const resolution = resolutionForUserRow({
    subscription_tier: "free",
    created_at: isoDaysFromNow(1),
    entitlement_version: 9,
  });
  assertEquals(resolution.effective_tier, "free");
  assertEquals(resolution.plan, "free");
  assertEquals(resolution.trial_active, false);
});

Deno.test("database entitlement errors fail closed", async () => {
  const client = mockSupabase([{
    data: null,
    error: { message: "database unavailable" },
  }]);
  const error = await assertRejects(
    () => resolveTierForUser(crypto.randomUUID(), client as never),
    Error,
    "AI entitlement could not be verified",
  ) as Error & { status?: number; code?: string };
  assertEquals(error.status, 503);
  assertEquals(error.code, "ai_entitlement_unavailable");
});

Deno.test("thrown entitlement transport failures are normalized and fail closed", async () => {
  const client = {
    from: () => ({
      select: () => ({
        eq: () => ({
          abortSignal: () => ({
            maybeSingle: () => Promise.reject(new DOMException("timed out")),
          }),
        }),
      }),
    }),
  };
  const error = await assertRejects(
    () => resolveTierForUser(crypto.randomUUID(), client as never),
    Error,
    "AI entitlement could not be verified",
  ) as Error & { status?: number; code?: string };
  assertEquals(error.status, 503);
  assertEquals(error.code, "ai_entitlement_unavailable");
});

Deno.test("a missing public user row fails closed instead of granting trial Pro", async () => {
  const client = mockSupabase([{ data: null }]);
  const error = await assertRejects(
    () => resolveTierForUser(crypto.randomUUID(), client as never),
    Error,
    "AI entitlement could not be verified",
  ) as Error & { status?: number; code?: string };
  assertEquals(error.status, 503);
  assertEquals(error.code, "ai_entitlement_unavailable");
});

Deno.test("entitlement resolution never reuses isolate-local state", async () => {
  const client = mockSupabase([
    {
      data: {
        subscription_tier: "pro",
        created_at: isoDaysAgo(30),
        entitlement_version: 10,
      },
    },
    {
      data: {
        subscription_tier: "free",
        created_at: isoDaysAgo(30),
        entitlement_version: 11,
      },
    },
  ]);
  const userId = crypto.randomUUID();

  assertEquals(
    await getTierForUser(userId, client as never),
    "pro",
  );
  assertEquals(
    await getTierForUser(userId, client as never),
    "free",
  );
  assertEquals(client.callCount, 2);
});
