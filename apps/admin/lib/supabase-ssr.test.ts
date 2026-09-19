import assert from "node:assert/strict";
import test from "node:test";
import { type CookieOptions, createServerClient } from "@supabase/ssr";

// Synthetic transport fixtures only; no hosted Auth calls or real sessions.
const cookieName = "sb-project-auth-token";
const publicKey = "sb_publishable_synthetic_test_key";
const user = {
  id: "00000000-0000-4000-8000-000000000001",
  aud: "authenticated",
  role: "authenticated",
  app_metadata: { provider: "google" },
  user_metadata: {},
  created_at: "2026-01-01T00:00:00Z",
};

function session(expiresAt: number) {
  const encode = (value: unknown) =>
    Buffer.from(JSON.stringify(value)).toString("base64url");
  return {
    access_token: `${encode({ alg: "HS256", typ: "JWT" })}.${
      encode({ sub: user.id, exp: expiresAt, aal: "aal2" })
    }.synthetic-signature`,
    refresh_token: "synthetic-refresh-token",
    expires_at: expiresAt,
    expires_in: 3600,
    token_type: "bearer",
    user,
  };
}

function cookieHarness(initialSession?: ReturnType<typeof session>) {
  const jar = new Map<string, string>();
  const writes: { name: string; value: string; options: CookieOptions }[] = [];
  if (initialSession) {
    jar.set(
      cookieName,
      `base64-${
        Buffer.from(JSON.stringify(initialSession)).toString("base64url")
      }`,
    );
  }
  return {
    jar,
    writes,
    client(fetchImplementation: typeof fetch) {
      return createServerClient("https://project.supabase.co", publicKey, {
        global: { fetch: fetchImplementation },
        cookies: {
          getAll: () => [...jar].map(([name, value]) => ({ name, value })),
          setAll(values) {
            for (const cookie of values) {
              writes.push(cookie);
              if (cookie.options.maxAge === 0) jar.delete(cookie.name);
              else jar.set(cookie.name, cookie.value);
            }
          },
        },
      });
    },
  };
}

test("SSR getUser without cookies does not invent a session or call Auth", async () => {
  const harness = cookieHarness();
  const client = harness.client(async () => {
    assert.fail("An absent session must not make an Auth request");
  });
  const result = await client.auth.getUser();
  assert.equal(result.data.user, null);
  assert.ok(result.error);
  assert.equal(harness.writes.length, 0);
});

test("SSR refresh writes reusable cookies and validates the refreshed user", async () => {
  const now = Math.floor(Date.now() / 1000);
  const refreshed = session(now + 3600);
  const harness = cookieHarness(session(now - 3600));
  let refreshRequests = 0;
  let userRequests = 0;
  const transport: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    const headers = new Headers(init?.headers);
    assert.equal(headers.get("apikey"), publicKey);
    if (url.pathname === "/auth/v1/token") {
      refreshRequests++;
      assert.equal(url.searchParams.get("grant_type"), "refresh_token");
      assert.equal(
        JSON.parse(String(init?.body)).refresh_token,
        "synthetic-refresh-token",
      );
      return Response.json(refreshed);
    }
    assert.equal(url.pathname, "/auth/v1/user");
    assert.equal(
      headers.get("Authorization"),
      `Bearer ${refreshed.access_token}`,
    );
    userRequests++;
    return Response.json(user);
  };

  const result = await harness.client(transport).auth.getUser();
  assert.equal(result.error, null);
  assert.equal(result.data.user?.id, user.id);
  assert.equal(refreshRequests, 1);
  assert.equal(userRequests, 1);
  const written = harness.writes.find((cookie) => cookie.name === cookieName);
  assert.ok(written);
  assert.equal(written.options.path, "/");
  assert.equal(written.options.sameSite, "lax");
  assert.ok((written.options.maxAge ?? 0) > 0);

  const nextRequest = await harness.client(transport).auth.getUser();
  assert.equal(nextRequest.error, null);
  assert.equal(nextRequest.data.user?.id, user.id);
  assert.equal(
    refreshRequests,
    1,
    "The next request must reuse the refreshed cookie",
  );
  assert.equal(
    userRequests,
    2,
    "A cached cookie is not a substitute for getUser validation",
  );
});

test("SSR invalid refresh removes the stale session and returns no user", async (context) => {
  context.mock.method(console, "error", () => {});
  const harness = cookieHarness(session(Math.floor(Date.now() / 1000) - 3600));
  let requests = 0;
  const client = harness.client(async (input) => {
    requests++;
    assert.equal(new URL(String(input)).pathname, "/auth/v1/token");
    return Response.json({
      code: "refresh_token_not_found",
      message: "Invalid refresh token",
    }, {
      status: 400,
      headers: { "X-Supabase-Api-Version": "2024-01-01" },
    });
  });
  const result = await client.auth.getUser();
  assert.equal(result.data.user, null);
  assert.ok(result.error);
  assert.equal(result.error.code, "refresh_token_not_found");
  assert.equal(requests, 1);
  assert.equal(harness.jar.has(cookieName), false);
  assert.ok(
    harness.writes.some((cookie) =>
      cookie.name === cookieName && cookie.options.maxAge === 0
    ),
  );
});
