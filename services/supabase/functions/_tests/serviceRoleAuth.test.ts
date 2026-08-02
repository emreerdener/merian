import { assertEquals, assertThrows } from "@std/assert";
import {
  authorizeServiceRoleRequest,
  requireServerApiKey,
  resolveServerApiKey,
  ServerApiKeyConfigurationError,
  type ServiceRoleAuthOptions,
} from "../_shared/serviceRoleAuth.ts";

const LEGACY_SERVICE_ROLE_KEY = [
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
  "eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJzZXJ2aWNlX3JvbGUifQ",
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
].join(".");
const LEGACY_ANON_KEY = [
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
  "eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJhbm9uIn0",
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
].join(".");
const SHORT_SIGNATURE_SERVICE_ROLE_KEY = [
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
  "eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJzZXJ2aWNlX3JvbGUifQ",
  "placeholder",
].join(".");
const fakeCurrentSecretKey = (label: string) =>
  ["sb", "secret", label, "a".repeat(20)].join("_");
const DEFAULT_SECRET_KEY = fakeCurrentSecretKey("default-key");
const WORKER_SECRET_KEY = fakeCurrentSecretKey("worker-key");
const EXPLICIT_SECRET_KEY = fakeCurrentSecretKey("explicit-key");
const SYNCHRONIZED_SECRET_KEY = fakeCurrentSecretKey("synchronized-key");
const INVALID_SECRET_KEY = `${fakeCurrentSecretKey("invalid")}!`;
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
      LEGACY_ANON_KEY,
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

Deno.test("authorizeServiceRoleRequest does not accept repository-specific secret headers", () => {
  const result = authorizeServiceRoleRequest(
    request({ "x-supabase-server-key": DEFAULT_SECRET_KEY }),
    {
      envSecretKeys: SECRET_KEYS,
    },
  );

  assertEquals(result, {
    ok: false,
    reason: "missing_token",
  });
});

Deno.test("authorizeServiceRoleRequest fails closed on invalid secret-key JSON", () => {
  for (
    const invalidConfiguration of [
      "{",
      "[]",
      DEFAULT_SECRET_KEY,
      JSON.stringify(DEFAULT_SECRET_KEY),
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

Deno.test("authorizeServiceRoleRequest keeps the synchronized hosted key available during platform configuration incidents", () => {
  const result = authorizeServiceRoleRequest(
    request({ apikey: SYNCHRONIZED_SECRET_KEY }),
    {
      envSynchronizedServerApiKey: SYNCHRONIZED_SECRET_KEY,
      envSecretKeys: "{",
    },
  );

  assertEquals(result, {
    ok: true,
    serverApiKey: SYNCHRONIZED_SECRET_KEY,
  });
});

Deno.test("authorizeServiceRoleRequest supports the singular local secret-key fallback", () => {
  assertEquals(
    authorizeServiceRoleRequest(
      request({ apikey: WORKER_SECRET_KEY }),
      {
        envSecretKey: WORKER_SECRET_KEY,
      },
    ),
    {
      ok: true,
      serverApiKey: WORKER_SECRET_KEY,
    },
  );
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

Deno.test("server-key resolution prefers explicit, synchronized, then platform-managed keys", () => {
  assertEquals(
    resolveServerApiKey({
      envServerApiKey: EXPLICIT_SECRET_KEY,
      envSynchronizedServerApiKey: SYNCHRONIZED_SECRET_KEY,
      envSecretKeys: SECRET_KEYS,
      envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
    }),
    { ok: true, serverApiKey: EXPLICIT_SECRET_KEY },
  );
  assertEquals(
    resolveServerApiKey({
      envSynchronizedServerApiKey: SYNCHRONIZED_SECRET_KEY,
      envSecretKeys: SECRET_KEYS,
      envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
    }),
    { ok: true, serverApiKey: SYNCHRONIZED_SECRET_KEY },
  );
  assertEquals(
    resolveServerApiKey({
      envSecretKey: WORKER_SECRET_KEY,
      envSecretKeys: SECRET_KEYS,
      envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
    }),
    { ok: true, serverApiKey: DEFAULT_SECRET_KEY },
  );
});

Deno.test("server-key resolution supports singular and legacy fallbacks and fails without a key", () => {
  assertEquals(
    resolveServerApiKey({
      envSecretKey: WORKER_SECRET_KEY,
    }),
    { ok: true, serverApiKey: WORKER_SECRET_KEY },
  );
  assertEquals(
    resolveServerApiKey({
      envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
    }),
    { ok: true, serverApiKey: LEGACY_SERVICE_ROLE_KEY },
  );
  assertEquals(
    resolveServerApiKey({}),
    { ok: false, reason: "no_configured_keys" },
  );
  assertEquals(
    resolveServerApiKey({ envSecretKeys: "{" }),
    { ok: false, reason: "invalid_secret_key_configuration" },
  );
  assertEquals(
    resolveServerApiKey({ envSecretKeys: DEFAULT_SECRET_KEY }),
    { ok: false, reason: "invalid_secret_key_configuration" },
  );
  assertEquals(
    resolveServerApiKey({
      envSecretKeys: JSON.stringify(DEFAULT_SECRET_KEY),
    }),
    { ok: false, reason: "invalid_secret_key_configuration" },
  );
});

Deno.test("server-key resolution rejects unprivileged or malformed configured keys", () => {
  for (
    const invalidOptions of [
      { envServerApiKey: "sb_publishable_public-key" },
      { envServerApiKey: "sb_secret_placeholder" },
      { envServerApiKey: INVALID_SECRET_KEY },
      { envServerApiKey: LEGACY_ANON_KEY },
      { envServerApiKey: "not-a-server-key" },
      { envSynchronizedServerApiKey: "sb_publishable_public-key" },
      { envSynchronizedServerApiKey: "sb_secret_placeholder" },
      { envSynchronizedServerApiKey: INVALID_SECRET_KEY },
      { envSynchronizedServerApiKey: LEGACY_ANON_KEY },
      { envSynchronizedServerApiKey: "not-a-server-key" },
      { envSecretKey: "sb_publishable_public-key" },
      { envSecretKey: INVALID_SECRET_KEY },
      { envSecretKey: LEGACY_SERVICE_ROLE_KEY },
      { envServiceRoleKey: DEFAULT_SECRET_KEY },
      { envServiceRoleKey: LEGACY_ANON_KEY },
      { envServiceRoleKey: SHORT_SIGNATURE_SERVICE_ROLE_KEY },
      { envServiceRoleKey: "not-a-jwt" },
    ]
  ) {
    assertEquals(
      resolveServerApiKey(invalidOptions),
      { ok: false, reason: "invalid_secret_key_configuration" },
    );
  }
});

Deno.test("authorization fails closed when a public key is placed in a privileged variable", () => {
  assertEquals(
    authorizeServiceRoleRequest(
      request({ apikey: "sb_publishable_public-key" }),
      { envServerApiKey: "sb_publishable_public-key" },
    ),
    { ok: false, reason: "invalid_secret_key_configuration" },
  );
  assertEquals(
    authorizeServiceRoleRequest(
      request({
        Authorization: `Bearer ${LEGACY_ANON_KEY}`,
        apikey: LEGACY_ANON_KEY,
      }),
      { envServiceRoleKey: LEGACY_ANON_KEY },
    ),
    { ok: false, reason: "invalid_secret_key_configuration" },
  );
});

Deno.test("required server-key resolution fails with a typed configuration error", () => {
  const error = assertThrows(
    () => requireServerApiKey({}),
    ServerApiKeyConfigurationError,
    "no_configured_keys",
  );
  assertEquals(error.reason, "no_configured_keys");
});

Deno.test("authorizeServiceRoleRequest accepts an exact explicit deployment key", () => {
  assertEquals(
    authorizeServiceRoleRequest(
      request({ apikey: EXPLICIT_SECRET_KEY }),
      {
        envServerApiKey: EXPLICIT_SECRET_KEY,
        envSecretKeys: SECRET_KEYS,
        envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
      },
    ),
    { ok: true, serverApiKey: EXPLICIT_SECRET_KEY },
  );
});

Deno.test("authorizeServiceRoleRequest accepts an exact synchronized hosted key", () => {
  assertEquals(
    authorizeServiceRoleRequest(
      request({ apikey: SYNCHRONIZED_SECRET_KEY }),
      {
        envSynchronizedServerApiKey: SYNCHRONIZED_SECRET_KEY,
        envSecretKeys: SECRET_KEYS,
        envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
      },
    ),
    { ok: true, serverApiKey: SYNCHRONIZED_SECRET_KEY },
  );
});

Deno.test("exact synchronized authorization is not vetoed by malformed unrelated sources", () => {
  for (
    const unrelatedConfiguration of [
      { envServiceRoleKey: SYNCHRONIZED_SECRET_KEY },
      { envServiceRoleKey: "not-a-jwt" },
      { envSecretKey: LEGACY_SERVICE_ROLE_KEY },
      { envSecretKey: "not-a-secret-key" },
      { envSecretKeys: JSON.stringify({ default: LEGACY_SERVICE_ROLE_KEY }) },
    ]
  ) {
    assertEquals(
      authorizeServiceRoleRequest(
        request({ apikey: SYNCHRONIZED_SECRET_KEY }),
        {
          ...unrelatedConfiguration,
          envSynchronizedServerApiKey: SYNCHRONIZED_SECRET_KEY,
        },
      ),
      { ok: true, serverApiKey: SYNCHRONIZED_SECRET_KEY },
    );
  }
});

Deno.test("exact platform-dictionary authorization is not vetoed by malformed lower-priority fallbacks", () => {
  assertEquals(
    authorizeServiceRoleRequest(
      request({ apikey: DEFAULT_SECRET_KEY }),
      {
        envSecretKeys: SECRET_KEYS,
        envSecretKey: LEGACY_SERVICE_ROLE_KEY,
        envServiceRoleKey: DEFAULT_SECRET_KEY,
      },
    ),
    { ok: true, serverApiKey: DEFAULT_SECRET_KEY },
  );
});

Deno.test("valid higher-priority outbound keys isolate malformed lower-priority sources", () => {
  assertEquals(
    resolveServerApiKey({
      envSynchronizedServerApiKey: SYNCHRONIZED_SECRET_KEY,
      envSecretKeys: "{",
      envSecretKey: LEGACY_SERVICE_ROLE_KEY,
      envServiceRoleKey: "not-a-jwt",
    }),
    { ok: true, serverApiKey: SYNCHRONIZED_SECRET_KEY },
  );
  assertEquals(
    resolveServerApiKey({
      envSecretKeys: SECRET_KEYS,
      envSecretKey: LEGACY_SERVICE_ROLE_KEY,
      envServiceRoleKey: DEFAULT_SECRET_KEY,
    }),
    { ok: true, serverApiKey: DEFAULT_SECRET_KEY },
  );
});

Deno.test("malformed higher-priority outbound sources never silently fall through", () => {
  assertEquals(
    resolveServerApiKey({
      envServerApiKey: INVALID_SECRET_KEY,
      envSynchronizedServerApiKey: SYNCHRONIZED_SECRET_KEY,
    }),
    { ok: false, reason: "invalid_secret_key_configuration" },
  );
  assertEquals(
    resolveServerApiKey({
      envSynchronizedServerApiKey: INVALID_SECRET_KEY,
      envSecretKeys: SECRET_KEYS,
    }),
    { ok: false, reason: "invalid_secret_key_configuration" },
  );
  assertEquals(
    resolveServerApiKey({
      envSecretKey: LEGACY_SERVICE_ROLE_KEY,
      envServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
    }),
    { ok: false, reason: "invalid_secret_key_configuration" },
  );
});

Deno.test("server-key sources preserve authorization and outbound invariants across every configuration state", () => {
  type SourceState = "absent" | "valid" | "invalid";
  const sourceStates: SourceState[] = ["absent", "valid", "invalid"];
  const validSourceKeys = [
    EXPLICIT_SECRET_KEY,
    SYNCHRONIZED_SECRET_KEY,
    DEFAULT_SECRET_KEY,
    WORKER_SECRET_KEY,
    LEGACY_SERVICE_ROLE_KEY,
  ];

  function optionsFor(states: SourceState[]): ServiceRoleAuthOptions {
    const [explicit, synchronized, named, singular, legacy] = states;
    return {
      envServerApiKey: explicit === "valid"
        ? EXPLICIT_SECRET_KEY
        : explicit === "invalid"
        ? INVALID_SECRET_KEY
        : "",
      envSynchronizedServerApiKey: synchronized === "valid"
        ? SYNCHRONIZED_SECRET_KEY
        : synchronized === "invalid"
        ? INVALID_SECRET_KEY
        : "",
      envSecretKeys: named === "valid"
        ? JSON.stringify({ default: DEFAULT_SECRET_KEY })
        : named === "invalid"
        ? "{"
        : "",
      envSecretKey: singular === "valid"
        ? WORKER_SECRET_KEY
        : singular === "invalid"
        ? LEGACY_SERVICE_ROLE_KEY
        : "",
      envServiceRoleKey: legacy === "valid"
        ? LEGACY_SERVICE_ROLE_KEY
        : legacy === "invalid"
        ? DEFAULT_SECRET_KEY
        : "",
    };
  }

  for (const explicit of sourceStates) {
    for (const synchronized of sourceStates) {
      for (const named of sourceStates) {
        for (const singular of sourceStates) {
          for (const legacy of sourceStates) {
            const states = [
              explicit,
              synchronized,
              named,
              singular,
              legacy,
            ];
            const options = optionsFor(states);
            const validIndexes = states.flatMap((state, index) =>
              state === "valid" ? [index] : []
            );
            const hasInvalidSource = states.includes("invalid");
            const preferredValidKey = validIndexes.length > 0
              ? validSourceKeys[validIndexes[0]]
              : null;

            for (const validIndex of validIndexes) {
              const key = validSourceKeys[validIndex];
              const headers: Record<string, string> = key.startsWith(
                  "sb_secret_",
                )
                ? { apikey: key }
                : {
                  apikey: key,
                  Authorization: `Bearer ${key}`,
                };
              assertEquals(
                authorizeServiceRoleRequest(request(headers), options),
                {
                  ok: true,
                  serverApiKey: preferredValidKey as string,
                },
                `Exact valid source ${validIndex} failed for ${
                  states.join("/")
                }`,
              );
            }

            assertEquals(
              authorizeServiceRoleRequest(
                request({ Authorization: "Bearer unmatched-user-token" }),
                options,
              ),
              hasInvalidSource
                ? {
                  ok: false,
                  reason: "invalid_secret_key_configuration",
                }
                : validIndexes.length === 0
                ? { ok: false, reason: "no_configured_keys" }
                : { ok: false, reason: "token_mismatch" },
              `Unmatched request was misclassified for ${states.join("/")}`,
            );

            const outbound = resolveServerApiKey(options);
            let expectedOutbound: ReturnType<typeof resolveServerApiKey>;
            if (explicit !== "absent") {
              expectedOutbound = explicit === "valid"
                ? { ok: true, serverApiKey: EXPLICIT_SECRET_KEY }
                : {
                  ok: false,
                  reason: "invalid_secret_key_configuration",
                };
            } else if (synchronized !== "absent") {
              expectedOutbound = synchronized === "valid"
                ? { ok: true, serverApiKey: SYNCHRONIZED_SECRET_KEY }
                : {
                  ok: false,
                  reason: "invalid_secret_key_configuration",
                };
            } else if (named === "valid") {
              expectedOutbound = {
                ok: true,
                serverApiKey: DEFAULT_SECRET_KEY,
              };
            } else if (singular !== "absent") {
              expectedOutbound = singular === "valid"
                ? { ok: true, serverApiKey: WORKER_SECRET_KEY }
                : {
                  ok: false,
                  reason: "invalid_secret_key_configuration",
                };
            } else if (legacy !== "absent") {
              expectedOutbound = legacy === "valid"
                ? { ok: true, serverApiKey: LEGACY_SERVICE_ROLE_KEY }
                : {
                  ok: false,
                  reason: "invalid_secret_key_configuration",
                };
            } else {
              expectedOutbound = named === "invalid"
                ? {
                  ok: false,
                  reason: "invalid_secret_key_configuration",
                }
                : { ok: false, reason: "no_configured_keys" };
            }
            assertEquals(
              outbound,
              expectedOutbound,
              `Outbound resolution failed for ${states.join("/")}`,
            );
          }
        }
      }
    }
  }
});

Deno.test("malformed configured values are never normalized into valid candidates", () => {
  const paddedKey = ` ${SYNCHRONIZED_SECRET_KEY} `;
  assertEquals(
    resolveServerApiKey({
      envSynchronizedServerApiKey: paddedKey,
    }),
    { ok: false, reason: "invalid_secret_key_configuration" },
  );
  assertEquals(
    authorizeServiceRoleRequest(
      request({ apikey: SYNCHRONIZED_SECRET_KEY }),
      { envSynchronizedServerApiKey: paddedKey },
    ),
    { ok: false, reason: "invalid_secret_key_configuration" },
  );
  assertEquals(
    authorizeServiceRoleRequest(
      request({ apikey: DEFAULT_SECRET_KEY }),
      {
        envSynchronizedServerApiKey: SYNCHRONIZED_SECRET_KEY,
        envServiceRoleKey: DEFAULT_SECRET_KEY,
      },
    ),
    { ok: false, reason: "invalid_secret_key_configuration" },
  );
});

Deno.test("synchronized deployment fallback supports the exact legacy key during overlap", () => {
  assertEquals(
    authorizeServiceRoleRequest(
      request({
        apikey: LEGACY_SERVICE_ROLE_KEY,
        authorization: `Bearer ${LEGACY_SERVICE_ROLE_KEY}`,
      }),
      {
        envSynchronizedServerApiKey: LEGACY_SERVICE_ROLE_KEY,
      },
    ),
    { ok: true, serverApiKey: LEGACY_SERVICE_ROLE_KEY },
  );
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
