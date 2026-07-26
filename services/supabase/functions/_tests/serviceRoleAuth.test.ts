import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { authorizeServiceRoleRequest } from "../_shared/serviceRoleAuth.ts";

const LEGACY_SERVICE_ROLE_KEY = "legacy-service-role-key";
const DEFAULT_SECRET_KEY = "sb_secret_default-key";
const WORKER_SECRET_KEY = "sb_secret_worker-key";
const SECRET_KEYS = JSON.stringify({
  default: DEFAULT_SECRET_KEY,
  worker: WORKER_SECRET_KEY,
});

function request(headers: HeadersInit = {}): Request {
  return new Request("https://example.test", { headers });
}

Deno.test("authorizeServiceRoleRequest accepts the exact legacy service-role key", () => {
  const result = authorizeServiceRoleRequest(
    request({ Authorization: `Bearer ${LEGACY_SERVICE_ROLE_KEY}` }),
    {
      envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
      envSecretKeys: SECRET_KEYS,
    },
  );

  assertEquals(result, {
    ok: true,
    serverApiKey: DEFAULT_SECRET_KEY,
  });
});

Deno.test("authorizeServiceRoleRequest accepts every exact named secret key", () => {
  for (const secretKey of [DEFAULT_SECRET_KEY, WORKER_SECRET_KEY]) {
    const result = authorizeServiceRoleRequest(
      request({ apikey: secretKey }),
      {
        envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
        envSecretKeys: SECRET_KEYS,
      },
    );

    assertEquals(result, {
      ok: true,
      serverApiKey: DEFAULT_SECRET_KEY,
    });
  }
});

Deno.test("authorizeServiceRoleRequest rejects public API credentials", () => {
  for (
    const unprivilegedToken of [
      "sb_publishable_public-key",
      "legacy-anon-jwt",
    ]
  ) {
    const result = authorizeServiceRoleRequest(
      request(
        unprivilegedToken.startsWith("sb_publishable_")
          ? { apikey: unprivilegedToken }
          : {
            Authorization: `Bearer ${unprivilegedToken}`,
            apikey: unprivilegedToken,
          },
      ),
      {
        envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
        envSecretKeys: SECRET_KEYS,
      },
    );

    assertEquals(result, { ok: false, reason: "token_mismatch" });
  }
});

Deno.test("authorizeServiceRoleRequest rejects authenticated user request formats", () => {
  assertEquals(
    authorizeServiceRoleRequest(
      request({
        Authorization: "Bearer authenticated-user-jwt",
        apikey: "sb_publishable_public-key",
      }),
      {
        envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
        envSecretKeys: SECRET_KEYS,
      },
    ),
    { ok: false, reason: "conflicting_credentials" },
  );

  assertEquals(
    authorizeServiceRoleRequest(
      request({ Authorization: "Bearer authenticated-user-jwt" }),
      {
        envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
        envSecretKeys: SECRET_KEYS,
      },
    ),
    { ok: false, reason: "token_mismatch" },
  );
});

Deno.test("authorizeServiceRoleRequest rejects conflicting credentials before matching", () => {
  const result = authorizeServiceRoleRequest(
    request({
      Authorization: "Bearer authenticated-user-jwt",
      apikey: WORKER_SECRET_KEY,
    }),
    {
      envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
      envSecretKeys: SECRET_KEYS,
    },
  );

  assertEquals(result, {
    ok: false,
    reason: "conflicting_credentials",
  });
});

Deno.test("authorizeServiceRoleRequest rejects malformed authorization headers", () => {
  const result = authorizeServiceRoleRequest(
    request({ Authorization: "Basic credential" }),
    {
      envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
      envSecretKeys: SECRET_KEYS,
    },
  );

  assertEquals(result, {
    ok: false,
    reason: "invalid_authorization_header",
  });
});

Deno.test("authorizeServiceRoleRequest accepts non-JWT secret keys only through apikey", () => {
  const result = authorizeServiceRoleRequest(
    request({ Authorization: `Bearer ${DEFAULT_SECRET_KEY}` }),
    {
      envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
      envSecretKeys: SECRET_KEYS,
    },
  );

  assertEquals(result, {
    ok: false,
    reason: "invalid_credential_transport",
  });
});

Deno.test("authorizeServiceRoleRequest fails closed on invalid secret-key JSON", () => {
  for (
    const invalidConfiguration of [
      "{",
      "[]",
      JSON.stringify({ default: "sb_publishable_public-key" }),
      JSON.stringify({ default: DEFAULT_SECRET_KEY, worker: 42 }),
    ]
  ) {
    const result = authorizeServiceRoleRequest(
      request({ apikey: DEFAULT_SECRET_KEY }),
      {
        envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
        envSecretKeys: invalidConfiguration,
      },
    );

    assertEquals(result, {
      ok: false,
      reason: "invalid_secret_key_configuration",
    });
  }
});

Deno.test("authorizeServiceRoleRequest keeps the exact legacy key available during secret-key configuration incidents", () => {
  const result = authorizeServiceRoleRequest(
    request({ Authorization: `Bearer ${LEGACY_SERVICE_ROLE_KEY}` }),
    {
      envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
      envSecretKeys: "{",
    },
  );

  assertEquals(result, {
    ok: true,
    serverApiKey: LEGACY_SERVICE_ROLE_KEY,
  });
});

Deno.test("authorizeServiceRoleRequest supports named-secret-only server configuration", () => {
  const result = authorizeServiceRoleRequest(
    request({ apikey: WORKER_SECRET_KEY }),
    {
      envServiceRoleKey: "",
      envSecretKeys: SECRET_KEYS,
    },
  );

  assertEquals(result, {
    ok: true,
    serverApiKey: DEFAULT_SECRET_KEY,
  });
});

Deno.test("authorizeServiceRoleRequest rejects requests when no server key is configured", () => {
  assertEquals(
    authorizeServiceRoleRequest(
      request({ apikey: DEFAULT_SECRET_KEY }),
      {
        envServiceRoleKey: "",
        envSecretKeys: "",
      },
    ),
    { ok: false, reason: "no_configured_keys" },
  );
  assertEquals(
    authorizeServiceRoleRequest(request(), {
      envServiceRoleKey: "",
      envSecretKeys: "",
    }),
    { ok: false, reason: "missing_token" },
  );
});
