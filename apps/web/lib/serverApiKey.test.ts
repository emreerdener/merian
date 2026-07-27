import assert from "node:assert/strict";
import test from "node:test";

import { resolveServerApiKeySources } from "./serverApiKey.ts";

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
    resolveServerApiKeySources({}),
    { ok: false, reason: "missing_server_api_key" },
  );
});
