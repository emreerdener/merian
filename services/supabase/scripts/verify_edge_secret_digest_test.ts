import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  listedSecretDigest,
  sha256Hex,
  verifyListedServerApiKeyDigest,
} from "./verify_edge_secret_digest.ts";

const SECRET_NAME = "MERIAN_SUPABASE_SERVER_API_KEY";
const SERVER_API_KEY = ["sb", "secret", "test", "a".repeat(24)].join("_");
const OTHER_DIGEST = "b".repeat(64);

Deno.test("SHA-256 helper returns lowercase hexadecimal", async () => {
  assertEquals(
    await sha256Hex("hello"),
    "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
  );
});

Deno.test("listed secret parser selects one exact SHA-256 digest", () => {
  assertEquals(
    listedSecretDigest(
      [
        { name: "OTHER_SECRET", value: OTHER_DIGEST },
        { name: SECRET_NAME, value: OTHER_DIGEST.toUpperCase() },
      ],
      SECRET_NAME,
    ),
    OTHER_DIGEST,
  );
});

Deno.test("listed secret parser rejects malformed, missing, or duplicate matches", () => {
  for (
    const payload of [
      null,
      {},
      [],
      [{ name: SECRET_NAME, value: "not-a-digest" }],
      [
        { name: SECRET_NAME, value: OTHER_DIGEST },
        { name: SECRET_NAME, value: OTHER_DIGEST },
      ],
    ]
  ) {
    assertThrows(
      () => listedSecretDigest(payload, SECRET_NAME),
      Error,
    );
  }
  assertThrows(
    () => listedSecretDigest([], "invalid-secret-name"),
    Error,
    "Invalid Edge Function secret name",
  );
});

Deno.test("server API key digest verification accepts only an exact match", async () => {
  const digest = await sha256Hex(SERVER_API_KEY);
  await verifyListedServerApiKeyDigest(
    [{ name: SECRET_NAME, value: digest }],
    SECRET_NAME,
    SERVER_API_KEY,
  );

  await assertRejects(
    () =>
      verifyListedServerApiKeyDigest(
        [{ name: SECRET_NAME, value: OTHER_DIGEST }],
        SECRET_NAME,
        SERVER_API_KEY,
      ),
    Error,
    "does not match",
  );
});

Deno.test("server API key digest verification rejects malformed plaintext safely", async () => {
  const malformedKey = "not-a-server-api-key";
  const error = await assertRejects(
    () =>
      verifyListedServerApiKeyDigest(
        [{ name: SECRET_NAME, value: OTHER_DIGEST }],
        SECRET_NAME,
        malformedKey,
      ),
    Error,
    "invalid_secret_key_configuration",
  );
  assertEquals(error.message.includes(malformedKey), false);
});
