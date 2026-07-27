import assert from "node:assert/strict";
import test from "node:test";

import {
  resolveServerApiKeySources,
  type ServerApiKeyResolution,
} from "./serverApiKey.ts";

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
const EXPLICIT_SECRET_KEY = fakeCurrentSecretKey("explicit");
const DEFAULT_SECRET_KEY = fakeCurrentSecretKey("default");
const WORKER_SECRET_KEY = fakeCurrentSecretKey("worker");
const INVALID_SECRET_KEY = `${fakeCurrentSecretKey("invalid")}!`;

test("server API key resolution prefers explicit, default, named, then legacy", () => {
  assert.deepEqual(
    resolveServerApiKeySources({
      explicitServerApiKey: EXPLICIT_SECRET_KEY,
      platformSecretKeys: JSON.stringify({
        worker: WORKER_SECRET_KEY,
        default: DEFAULT_SECRET_KEY,
      }),
      legacyServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
    }),
    { ok: true, key: EXPLICIT_SECRET_KEY },
  );
  assert.deepEqual(
    resolveServerApiKeySources({
      platformSecretKeys: JSON.stringify({
        worker: WORKER_SECRET_KEY,
        default: DEFAULT_SECRET_KEY,
      }),
      legacyServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
    }),
    { ok: true, key: DEFAULT_SECRET_KEY },
  );
  assert.deepEqual(
    resolveServerApiKeySources({
      platformSecretKeys: JSON.stringify({ worker: WORKER_SECRET_KEY }),
      legacyServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
    }),
    { ok: true, key: WORKER_SECRET_KEY },
  );
  assert.deepEqual(
    resolveServerApiKeySources({
      legacyServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
    }),
    { ok: true, key: LEGACY_SERVICE_ROLE_KEY },
  );
});

test("server API key resolution rejects publishable, anon, and malformed values", () => {
  for (
    const sources of [
      { explicitServerApiKey: "sb_publishable_public" },
      { explicitServerApiKey: "sb_secret_placeholder" },
      { explicitServerApiKey: INVALID_SECRET_KEY },
      { explicitServerApiKey: LEGACY_ANON_KEY },
      { explicitServerApiKey: "not-a-server-key" },
      { legacyServiceRoleKey: LEGACY_ANON_KEY },
      { legacyServiceRoleKey: SHORT_SIGNATURE_SERVICE_ROLE_KEY },
      { legacyServiceRoleKey: "not-a-jwt" },
      {
        platformSecretKeys: JSON.stringify({
          default: "sb_publishable_public",
        }),
      },
      { platformSecretKeys: "{" },
    ]
  ) {
    assert.deepEqual(
      resolveServerApiKeySources(sources),
      { ok: false, reason: "invalid_server_api_key_configuration" },
    );
  }
});

test("server API key resolution permits only a validated fallback during dictionary incidents", () => {
  assert.deepEqual(
    resolveServerApiKeySources({
      explicitServerApiKey: EXPLICIT_SECRET_KEY,
      platformSecretKeys: "{",
    }),
    { ok: true, key: EXPLICIT_SECRET_KEY },
  );
  assert.deepEqual(
    resolveServerApiKeySources({
      platformSecretKeys: "{",
      legacyServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
    }),
    { ok: true, key: LEGACY_SERVICE_ROLE_KEY },
  );
  assert.deepEqual(
    resolveServerApiKeySources({}),
    { ok: false, reason: "missing_server_api_key" },
  );
});

test("valid web server sources isolate malformed lower-priority migration fallbacks", () => {
  assert.deepEqual(
    resolveServerApiKeySources({
      explicitServerApiKey: EXPLICIT_SECRET_KEY,
      platformSecretKeys: "{",
      legacyServiceRoleKey: "not-a-jwt",
    }),
    { ok: true, key: EXPLICIT_SECRET_KEY },
  );
  assert.deepEqual(
    resolveServerApiKeySources({
      platformSecretKeys: JSON.stringify({
        default: DEFAULT_SECRET_KEY,
      }),
      legacyServiceRoleKey: DEFAULT_SECRET_KEY,
    }),
    { ok: true, key: DEFAULT_SECRET_KEY },
  );
});

test("web server-key sources preserve strict precedence across every configuration state", () => {
  type SourceState = "absent" | "valid" | "invalid";
  const sourceStates: SourceState[] = ["absent", "valid", "invalid"];

  for (const explicit of sourceStates) {
    for (const named of sourceStates) {
      for (const legacy of sourceStates) {
        const resolution = resolveServerApiKeySources({
          explicitServerApiKey: explicit === "valid"
            ? EXPLICIT_SECRET_KEY
            : explicit === "invalid"
            ? INVALID_SECRET_KEY
            : "",
          platformSecretKeys: named === "valid"
            ? JSON.stringify({ default: DEFAULT_SECRET_KEY })
            : named === "invalid"
            ? "{"
            : "",
          legacyServiceRoleKey: legacy === "valid"
            ? LEGACY_SERVICE_ROLE_KEY
            : legacy === "invalid"
            ? DEFAULT_SECRET_KEY
            : "",
        });

        const expected: ServerApiKeyResolution = explicit !== "absent"
          ? explicit === "valid" ? { ok: true, key: EXPLICIT_SECRET_KEY } : {
            ok: false,
            reason: "invalid_server_api_key_configuration",
          }
          : named === "valid"
          ? { ok: true, key: DEFAULT_SECRET_KEY }
          : legacy !== "absent"
          ? legacy === "valid" ? { ok: true, key: LEGACY_SERVICE_ROLE_KEY } : {
            ok: false,
            reason: "invalid_server_api_key_configuration",
          }
          : named === "invalid"
          ? {
            ok: false,
            reason: "invalid_server_api_key_configuration",
          }
          : { ok: false, reason: "missing_server_api_key" };

        assert.deepEqual(
          resolution,
          expected,
          `Resolution failed for ${explicit}/${named}/${legacy}`,
        );
      }
    }
  }
});

test("web server resolution never normalizes malformed credentials", () => {
  assert.deepEqual(
    resolveServerApiKeySources({
      explicitServerApiKey: ` ${EXPLICIT_SECRET_KEY} `,
      platformSecretKeys: JSON.stringify({
        default: DEFAULT_SECRET_KEY,
      }),
      legacyServiceRoleKey: LEGACY_SERVICE_ROLE_KEY,
    }),
    { ok: false, reason: "invalid_server_api_key_configuration" },
  );
  assert.deepEqual(
    resolveServerApiKeySources({
      legacyServiceRoleKey: ` ${LEGACY_SERVICE_ROLE_KEY} `,
    }),
    { ok: false, reason: "invalid_server_api_key_configuration" },
  );
});
