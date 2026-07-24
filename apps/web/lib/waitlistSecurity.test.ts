import assert from "node:assert/strict";
import test from "node:test";
import {
  normalizedUserAgent,
  normalizeWaitlistEmail,
  parseAllowedHostnames,
  resolveTrustedClientIp,
  TURNSTILE_RESPONSE_MAX_BYTES,
  verifyTurnstileToken,
  waitlistIpHash,
} from "./waitlistSecurity.ts";

test("waitlist email normalization accepts bounded canonical addresses", () => {
  assert.equal(
    normalizeWaitlistEmail("  Person.Tag+beta@Example.COM  "),
    "person.tag+beta@example.com",
  );
  for (
    const invalid of [
      null,
      "",
      ".person@example.com",
      "person.@example.com",
      "person..tag@example.com",
      "person@example",
      "person@-example.com",
      `person@${"x".repeat(64)}.com`,
      `${"x".repeat(65)}@example.com`,
      `person@example.${"x".repeat(64)}`,
    ]
  ) {
    assert.equal(normalizeWaitlistEmail(invalid), null);
  }
});

test("waitlist metadata is bounded and client addresses use one trusted header", () => {
  assert.equal(
    normalizedUserAgent("  Example\tBrowser\r\n  1.0  "),
    "Example Browser 1.0",
  );
  assert.equal(normalizedUserAgent("x".repeat(600))?.length, 512);

  const headers = new Headers({
    "x-vercel-forwarded-for": "203.0.113.8, 10.0.0.1",
    "x-forwarded-for": "198.51.100.9",
  });
  assert.equal(
    resolveTrustedClientIp(headers, "x-vercel-forwarded-for"),
    "203.0.113.8",
  );
  assert.equal(resolveTrustedClientIp(headers, "x-untrusted-header"), null);
});

test("waitlist IP hashes are purpose-separated and rotate each UTC day", () => {
  const secret = "s".repeat(32);
  const first = waitlistIpHash(
    "203.0.113.8",
    secret,
    new Date("2026-07-24T23:59:59Z"),
  );
  const sameDay = waitlistIpHash(
    "203.0.113.8",
    secret,
    new Date("2026-07-24T01:00:00Z"),
  );
  const nextDay = waitlistIpHash(
    "203.0.113.8",
    secret,
    new Date("2026-07-25T00:00:00Z"),
  );

  assert.equal(first?.length, 64);
  assert.equal(first, sameDay);
  assert.notEqual(first, nextDay);
  assert.equal(first?.includes("203.0.113.8"), false);
});

test("Turnstile validation fails closed on action and hostname drift", async () => {
  const allowedHostnames = parseAllowedHostnames(
    "naturebook.earth, www.naturebook.earth",
  );
  const input = {
    token: "verified-token",
    secret: "secret".repeat(6),
    remoteIp: "203.0.113.8",
    requestId: "00000000-0000-0000-0000-000000000001",
    allowedHostnames,
  };

  const valid = await verifyTurnstileToken(
    input,
    turnstileFetch({
      success: true,
      action: "waitlist",
      hostname: "naturebook.earth",
    }),
  );
  assert.deepEqual(valid, { ok: true });

  const wrongAction = await verifyTurnstileToken(
    input,
    turnstileFetch({
      success: true,
      action: "login",
      hostname: "naturebook.earth",
    }),
  );
  assert.deepEqual(wrongAction, { ok: false, kind: "invalid" });

  const wrongHostname = await verifyTurnstileToken(
    input,
    turnstileFetch({
      success: true,
      action: "waitlist",
      hostname: "attacker.example",
    }),
  );
  assert.deepEqual(wrongHostname, { ok: false, kind: "invalid" });
});

test("Turnstile validation fails closed when the provider is unavailable", async () => {
  const result = await verifyTurnstileToken(
    {
      token: "verified-token",
      secret: "secret".repeat(6),
      remoteIp: "203.0.113.8",
      requestId: "00000000-0000-0000-0000-000000000001",
      allowedHostnames: new Set(["naturebook.earth"]),
    },
    (() => Promise.reject(new Error("network unavailable"))) as typeof fetch,
  );
  assert.deepEqual(result, { ok: false, kind: "unavailable" });
});

test("Turnstile validation rejects incomplete configuration before fetch", async () => {
  let fetched = false;
  const result = await verifyTurnstileToken(
    {
      token: "verified-token",
      secret: "",
      remoteIp: "203.0.113.8",
      requestId: "00000000-0000-0000-0000-000000000001",
      allowedHostnames: new Set(["naturebook.earth"]),
    },
    (async () => {
      fetched = true;
      return new Response();
    }) as typeof fetch,
  );

  assert.deepEqual(result, { ok: false, kind: "unavailable" });
  assert.equal(fetched, false);
});

test("Turnstile validation cancels an oversized chunked provider response", async () => {
  let canceled = false;
  const fetchImpl = (async () => {
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(
          new Uint8Array(TURNSTILE_RESPONSE_MAX_BYTES + 1),
        );
      },
      cancel() {
        canceled = true;
      },
    });
    return new Response(stream, {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }) as typeof fetch;

  const result = await verifyTurnstileToken(
    {
      token: "verified-token",
      secret: "secret".repeat(6),
      remoteIp: "203.0.113.8",
      requestId: "00000000-0000-0000-0000-000000000001",
      allowedHostnames: new Set(["naturebook.earth"]),
    },
    fetchImpl,
  );

  assert.deepEqual(result, { ok: false, kind: "unavailable" });
  assert.equal(canceled, true);
});

function turnstileFetch(
  payload: Record<string, unknown>,
): typeof fetch {
  return (async (_input, init) => {
    assert.equal(init?.method, "POST");
    assert.ok(String(init?.body).includes("idempotency_key="));
    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }) as typeof fetch;
}
