import {
  assert,
  assertEquals,
  assertMatch,
  assertNotEquals,
  assertStringIncludes,
} from "@std/assert";
import {
  generateHandoffSecret,
  isSecretHash,
  parseGhostMergeRequest,
  sha256Hex,
} from "../merge-ghost-profile/protocol.ts";
import {
  GhostMergeDatabaseError,
  mapDatabaseError,
} from "../merge-ghost-profile/db.ts";

const HANDOFF_ID = "550e8400-e29b-41d4-a716-446655440000";

Deno.test("ghost merge protocol - prepare binds an allowed provider subject", () => {
  assertEquals(
    parseGhostMergeRequest({
      operation: "prepare",
      provider: "apple",
      provider_subject: "001234.abcd9876.1234",
    }),
    {
      operation: "prepare",
      provider: "apple",
      providerSubject: "001234.abcd9876.1234",
    },
  );

  assertEquals(
    parseGhostMergeRequest({
      operation: "prepare",
      provider: "google",
      provider_subject: "109876543210987654321",
    }),
    {
      operation: "prepare",
      provider: "google",
      providerSubject: "109876543210987654321",
    },
  );
});

Deno.test("ghost merge protocol - prepare rejects unsupported providers and unsafe subjects", () => {
  const unsupported = parseGhostMergeRequest({
    operation: "prepare",
    provider: "github",
    provider_subject: "subject",
  });
  assert("status" in unsupported);
  assertEquals(unsupported.status, 400);

  const controlCharacter = parseGhostMergeRequest({
    operation: "prepare",
    provider: "google",
    provider_subject: "subject\ninjection",
  });
  assert("status" in controlCharacter);
  assertEquals(controlCharacter.status, 400);

  const c1ControlCharacter = parseGhostMergeRequest({
    operation: "prepare",
    provider: "google",
    provider_subject: "subject\u0085injection",
  });
  assert("status" in c1ControlCharacter);
  assertEquals(c1ControlCharacter.status, 400);

  const oversized = parseGhostMergeRequest({
    operation: "prepare",
    provider: "google",
    provider_subject: "a".repeat(256),
  });
  assert("status" in oversized);
  assertEquals(oversized.status, 400);
});

Deno.test("ghost merge protocol - completion accepts only a UUID and 256-bit secret", () => {
  const secret = generateHandoffSecret();
  assertEquals(
    parseGhostMergeRequest({
      operation: "complete",
      handoff_id: HANDOFF_ID.toUpperCase(),
      handoff_secret: secret,
    }),
    {
      operation: "complete",
      handoffId: HANDOFF_ID,
      handoffSecret: secret,
    },
  );

  for (
    const body of [
      {
        operation: "complete",
        handoff_id: "'; DROP TABLE users; --",
        handoff_secret: secret,
      },
      {
        operation: "complete",
        handoff_id: HANDOFF_ID,
        handoff_secret: "too-short",
      },
      {
        operation: "complete",
        handoff_id: HANDOFF_ID,
        handoff_secret: "a".repeat(43) + "=",
      },
    ]
  ) {
    const result = parseGhostMergeRequest(body);
    assert("status" in result);
    assertEquals(result.status, 400);
  }
});

Deno.test("ghost merge protocol - caller can no longer nominate a ghost UUID", () => {
  for (
    const body of [
      { ghost_id: HANDOFF_ID },
      {
        operation: "prepare",
        provider: "google",
        provider_subject: "subject",
        ghost_id: HANDOFF_ID,
      },
      {
        operation: "complete",
        handoff_id: HANDOFF_ID,
        handoff_secret: generateHandoffSecret(),
        target_user_id: HANDOFF_ID,
      },
    ]
  ) {
    const result = parseGhostMergeRequest(body);
    assert("status" in result);
    assertEquals(result.status, 400);
  }
});

Deno.test("ghost merge protocol - identity refresh is an explicit safe operation", () => {
  assertEquals(
    parseGhostMergeRequest({ operation: "refresh_identity" }),
    { operation: "refresh_identity" },
  );

  const result = parseGhostMergeRequest({
    operation: "refresh_identity",
    ghost_id: HANDOFF_ID,
  });
  assert("status" in result);
  assertEquals(result.status, 400);
});

Deno.test("ghost merge protocol - generated secrets have 256 bits of URL-safe material", () => {
  const secrets = new Set<string>();
  for (let index = 0; index < 256; index += 1) {
    const secret = generateHandoffSecret();
    assertEquals(secret.length, 43);
    assertMatch(secret, /^[A-Za-z0-9_-]{43}$/);
    secrets.add(secret);
  }
  assertEquals(secrets.size, 256);
});

Deno.test("ghost merge protocol - SHA-256 hashes are deterministic and non-reversible storage values", async () => {
  assertEquals(
    await sha256Hex("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );

  const firstSecret = generateHandoffSecret();
  const secondSecret = generateHandoffSecret();
  const firstHash = await sha256Hex(firstSecret);
  const secondHash = await sha256Hex(secondSecret);

  assert(isSecretHash(firstHash));
  assert(isSecretHash(secondHash));
  assertNotEquals(firstHash, firstSecret);
  assertNotEquals(firstHash, secondHash);
});

Deno.test("ghost merge database errors expose retryable transaction failures as 503", () => {
  for (const code of ["40001", "40P01", "55P03", "57014"]) {
    const mapped = mapDatabaseError(
      {
        code,
        message: "transaction could not complete",
        details: "",
        hint: "",
        name: "PostgrestError",
        toJSON: () => ({
          name: "PostgrestError",
          code,
          message: "transaction could not complete",
          details: "",
          hint: "",
        }),
      },
      "fallback",
    );

    assert(mapped instanceof GhostMergeDatabaseError);
    assertEquals(mapped.code, "merge_temporarily_unavailable");
    assertEquals(mapped.status, 503);
  }
});

Deno.test("ghost merge database errors expose guarded schema drift as 503", () => {
  for (
    const message of [
      "ghost_merge_schema_requires_composite_fk_policy",
      "ghost_merge_unhandled_reference",
      "ghost_merge_unclassified_reference",
      "ghost_merge_stale_reference_policy",
      "ghost_merge_blocked_reference",
      "ghost_merge_preserved_reference_present",
      "ghost_merge_invalid_source_profile_policy",
      "ghost_merge_invalid_scan_species_policy",
      "ghost_merge_unknown_policy_handler",
      "ghost_merge_orchestrator_source_drift",
      "ghost_merge_species_ledger_mismatch",
      "user_species_scan_count_underflow",
    ]
  ) {
    const mapped = mapDatabaseError(
      {
        code: "55000",
        message,
        details: "",
        hint: "",
        name: "PostgrestError",
        toJSON: () => ({
          name: "PostgrestError",
          code: "55000",
          message,
          details: "",
          hint: "",
        }),
      },
      "fallback",
    );

    assert(mapped instanceof GhostMergeDatabaseError);
    assertEquals(mapped.code, "merge_temporarily_unavailable");
    assertEquals(mapped.status, 503);
    assertStringIncludes(mapped.message, "guest data is unchanged");
  }
});

Deno.test("ghost merge cannot consume a bound sign-out purchase destination", () => {
  const mapped = mapDatabaseError(
    {
      code: "55P03",
      message: "signout_purchase_handoff_pending",
      details: "",
      hint: "",
      name: "PostgrestError",
      toJSON: () => ({
        name: "PostgrestError",
        code: "55P03",
        message: "signout_purchase_handoff_pending",
        details: "",
        hint: "",
      }),
    },
    "fallback",
  );

  assertEquals(mapped.code, "purchase_handoff_pending");
  assertEquals(mapped.status, 409);
  assertStringIncludes(mapped.message, "Finish signing out");
});
