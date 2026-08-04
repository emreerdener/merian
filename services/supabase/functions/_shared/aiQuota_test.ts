import {
  assert,
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "@std/assert";
import {
  AIQuotaError,
  type AIQuotaReservation,
  clientAddressForQuota,
  createAIProviderQuotaLease,
  deriveAIRequestId,
  hmacClientAddress,
  quotaErrorForDatabaseMessage,
  resolveAIRequestId,
  resolveQuotaIpHashSecret,
} from "./aiQuota.ts";

const REQUEST_ID = "00000000-0000-0000-0000-000000000123";
const SECRET = "test-only-ai-quota-hmac-secret-32-bytes";

Deno.test("AI request id prefers the validated body id", () => {
  const request = new Request("https://example.invalid", {
    headers: {
      "Idempotency-Key": "00000000-0000-0000-0000-000000000999",
    },
  });
  assertEquals(resolveAIRequestId(request, REQUEST_ID), REQUEST_ID);
});

Deno.test("AI request id uses a validated Idempotency-Key header", () => {
  const request = new Request("https://example.invalid", {
    headers: { "Idempotency-Key": REQUEST_ID.toUpperCase() },
  });
  assertEquals(resolveAIRequestId(request), REQUEST_ID);
});

Deno.test("invalid AI idempotency keys fail before database access", () => {
  const error = assertThrows(
    () =>
      resolveAIRequestId(
        new Request("https://example.invalid"),
        "attacker-controlled-arbitrary-key",
      ),
    AIQuotaError,
  );
  assertEquals(error.status, 400);
  assertEquals(error.code, "ai_request_id_invalid");
});

Deno.test("paid sub-operations derive stable, non-reversible UUIDs", async () => {
  const first = await deriveAIRequestId(
    REQUEST_ID,
    "audio-checksum:policy-v1",
  );
  const replay = await deriveAIRequestId(
    REQUEST_ID,
    "audio-checksum:policy-v1",
  );
  const differentMedia = await deriveAIRequestId(
    REQUEST_ID,
    "different-checksum:policy-v1",
  );

  assertEquals(first, replay);
  assertNotEquals(first, differentMedia);
  assert(
    /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(first),
  );
  assert(!first.includes("audio-checksum"));
});

Deno.test("quota address trusts proxy-observed headers and right-most forwarding peer", () => {
  assertEquals(
    clientAddressForQuota(
      new Headers({
        "x-real-ip": "203.0.113.8",
        "x-forwarded-for": "198.51.100.4, 192.0.2.7",
      }),
    ),
    "203.0.113.8",
  );
  assertEquals(
    clientAddressForQuota(
      new Headers({
        "x-forwarded-for": "attacker-value, 192.0.2.7",
      }),
    ),
    "192.0.2.7",
  );
  assertEquals(clientAddressForQuota(new Headers()), "unavailable");
});

Deno.test("quota IP HMAC is deterministic per day and rotates without exposing the IP", async () => {
  const address = "203.0.113.8";
  const first = await hmacClientAddress(
    address,
    SECRET,
    new Date("2026-07-23T12:00:00Z"),
  );
  const sameDay = await hmacClientAddress(
    address,
    SECRET,
    new Date("2026-07-23T23:59:59Z"),
  );
  const nextDay = await hmacClientAddress(
    address,
    SECRET,
    new Date("2026-07-24T00:00:00Z"),
  );

  assertEquals(first, sameDay);
  assertNotEquals(first, nextDay);
  assert(/^[0-9a-f]{64}$/.test(first));
  assert(!first.includes(address));
});

Deno.test("quota hashing fails closed when its dedicated secret is weak", async () => {
  let caught: unknown;
  try {
    await hmacClientAddress("203.0.113.8", "too-short");
  } catch (error) {
    caught = error;
  }
  assert(caught instanceof AIQuotaError);
  assertEquals(caught.status, 503);
  assertEquals(caught.code, "ai_quota_unavailable");
});

Deno.test("quota hashing uses an optional dedicated override or a server-only platform key", () => {
  const dedicated = `${SECRET}-dedicated`;
  const platform = `${SECRET}-platform`;
  assertEquals(
    resolveQuotaIpHashSecret({
      dedicatedSecret: ` ${dedicated} `,
      platformSecretKey: platform,
    }),
    dedicated,
  );
  assertEquals(
    resolveQuotaIpHashSecret({
      platformSecretKey: platform,
      serviceRoleKey: `${SECRET}-legacy`,
    }),
    platform,
  );
  assertEquals(
    resolveQuotaIpHashSecret({ serviceRoleKey: `${SECRET}-legacy` }),
    `${SECRET}-legacy`,
  );
  assertThrows(
    () =>
      resolveQuotaIpHashSecret({
        dedicatedSecret: "explicit-but-weak",
        platformSecretKey: platform,
      }),
    AIQuotaError,
  );
});

Deno.test("missing or withdrawn AI consent maps to a caller-safe 403", () => {
  const error = quotaErrorForDatabaseMessage(
    "ai_consent_required",
  );

  assertEquals(error.status, 403);
  assertEquals(error.code, "ai_consent_required");
  assertEquals(
    error.message,
    "Confirm you are 18 or older, accept the current Terms, and allow Google Gemini processing to continue.",
  );
});

function quotaReservation(): AIQuotaReservation {
  return {
    id: "00000000-0000-0000-0000-000000000321",
    requestId: REQUEST_ID,
    leaseToken: "00000000-0000-0000-0000-000000000654",
    leaseExpiresAt: "2026-07-23T12:10:00.000Z",
    attemptCount: 1,
    model: "gemini-2.5-flash",
    tier: {
      current_plan: "free",
      current_tier: "free",
      is_paid: false,
      scans_remaining: 0,
      scans_available_to_start: 0,
      in_flight_count: 0,
      effective_tier: "free",
      plan: "free",
      subscription_tier: "free",
      trial_active: false,
      user_exists: true,
      entitlement_version: 1,
    },
    policyVersion: 1,
    dailyLimit: 1,
    dailyRemaining: 0,
    originalAnalysisId: null,
    complimentaryClientScanId: null,
    flashFallbackUsed: false,
  };
}

Deno.test("provider commit fails closed and forwards the attempt fencing token", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const client = {
    rpc: (_name: string, args: Record<string, unknown>) => {
      calls.push(args);
      return {
        abortSignal: () =>
          Promise.resolve({
            data: null,
            error: { code: "P0001" },
          }),
      };
    },
  };
  const lease = createAIProviderQuotaLease(
    client as never,
    "00000000-0000-0000-0000-000000000111",
    quotaReservation(),
  );

  const error = await assertRejects(
    () => lease.commit(),
    AIQuotaError,
  );
  assertEquals(error.status, 503);
  assertEquals(error.code, "ai_quota_unavailable");
  assertEquals(
    calls[0]?.p_lease_token,
    quotaReservation().leaseToken,
  );
});

Deno.test("failed provider attempts transition committed leases without refunding", async () => {
  const states: unknown[] = [];
  const client = {
    rpc: (_name: string, args: Record<string, unknown>) => {
      states.push(args.p_final_state);
      return {
        abortSignal: () => Promise.resolve({ data: true, error: null }),
      };
    },
  };
  const lease = createAIProviderQuotaLease(
    client as never,
    "00000000-0000-0000-0000-000000000111",
    quotaReservation(),
  );

  await lease.commit();
  assertEquals(await lease.fail(), true);
  assertEquals(await lease.refund(), false);
  assertEquals(states, ["committed", "failed"]);
});
