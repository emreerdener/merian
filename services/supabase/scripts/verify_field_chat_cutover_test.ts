import { assertEquals, assertThrows } from "@std/assert";
import {
  FIELD_CHAT_CUTOVER_MIGRATION_ID,
  validateFieldChatCutoverRows,
} from "./verify_field_chat_cutover.ts";

function row(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    migration_id: FIELD_CHAT_CUTOVER_MIGRATION_ID,
    seeded_at: "2026-08-24 18:30:00+00",
    not_before_utc: "2026-08-25 00:00:00+00",
    activated_at: null,
    activated_candidate_sha: null,
    activated_migration_sha256: null,
    activated_explore_bundle_sha256: null,
    activated_insight_bundle_sha256: null,
    activated_species_dictionary_bundle_sha256: null,
    database_now: "2026-08-24 19:00:00+00",
    status: "pending",
    ...overrides,
  };
}

Deno.test("Field Chat cutover accepts pending, ready, and active states", () => {
  assertEquals(validateFieldChatCutoverRows([row()]).status, "pending");
  assertEquals(
    validateFieldChatCutoverRows([
      row({
        database_now: "2026-08-25 00:00:00+00",
        status: "ready",
      }),
    ]).status,
    "ready",
  );
  assertEquals(
    validateFieldChatCutoverRows([
      row({
        database_now: "2026-08-25 00:02:00+00",
        activated_at: "2026-08-25 00:01:00+00",
        activated_candidate_sha: "a".repeat(40),
        activated_migration_sha256: "b".repeat(64),
        activated_explore_bundle_sha256: "c".repeat(64),
        activated_insight_bundle_sha256: "d".repeat(64),
        activated_species_dictionary_bundle_sha256: "e".repeat(64),
        status: "active",
      }),
    ], "b".repeat(64)).status,
    "active",
  );
});

Deno.test("Field Chat cutover fails closed on missing or contradictory state", () => {
  for (
    const rows of [
      [],
      [row(), row()],
      [row({ migration_id: "unexpected" })],
      [row({ status: "unknown" })],
      [row({ database_now: "not-a-time" })],
      [row({ not_before_utc: "2026-08-25 00:00:01+00" })],
      [row({ database_now: "2026-08-25 00:00:00+00" })],
      [row({ not_before_utc: "2026-08-24 18:00:00+00" })],
      [row({ activated_at: "2026-08-25 00:01:00+00" })],
      [row({
        database_now: "2026-08-25 00:02:00+00",
        activated_at: "2026-08-25 00:01:00+00",
        activated_candidate_sha: "0".repeat(40),
        activated_migration_sha256: "b".repeat(64),
        activated_explore_bundle_sha256: "c".repeat(64),
        activated_insight_bundle_sha256: "d".repeat(64),
        activated_species_dictionary_bundle_sha256: "e".repeat(64),
        status: "active",
      })],
      [row({
        database_now: "2026-08-25 00:02:00+00",
        activated_at: "2026-08-25 00:01:00+00",
        activated_candidate_sha: "a".repeat(40),
        activated_migration_sha256: "b".repeat(64),
        activated_explore_bundle_sha256: "0".repeat(64),
        activated_insight_bundle_sha256: "d".repeat(64),
        activated_species_dictionary_bundle_sha256: "e".repeat(64),
        status: "active",
      })],
      [row({
        database_now: "2026-08-25 00:02:00+00",
        activated_at: "2026-08-24 23:59:00+00",
        activated_candidate_sha: "a".repeat(40),
        activated_migration_sha256: "b".repeat(64),
        activated_explore_bundle_sha256: "c".repeat(64),
        activated_insight_bundle_sha256: "d".repeat(64),
        activated_species_dictionary_bundle_sha256: "e".repeat(64),
        status: "active",
      })],
      [row({
        database_now: "2026-08-25 00:02:00+00",
        activated_at: "2026-08-25 00:01:00+00",
        activated_candidate_sha: "not-a-sha",
        activated_migration_sha256: "b".repeat(64),
        activated_explore_bundle_sha256: "c".repeat(64),
        activated_insight_bundle_sha256: "d".repeat(64),
        activated_species_dictionary_bundle_sha256: "e".repeat(64),
        status: "active",
      })],
      [row({
        database_now: "2026-08-25 00:02:00+00",
        activated_at: "2026-08-25 00:01:00+00",
        activated_candidate_sha: "a".repeat(40),
        activated_migration_sha256: "b".repeat(64),
        activated_explore_bundle_sha256: "c".repeat(64),
        activated_insight_bundle_sha256: "d".repeat(64),
        activated_species_dictionary_bundle_sha256: "e".repeat(64),
        status: "active",
      })],
    ]
  ) {
    assertThrows(() => validateFieldChatCutoverRows(rows, "c".repeat(64)));
  }
});

Deno.test("Field Chat cutover requires all three bundle digests as one evidence set", () => {
  assertThrows(() =>
    validateFieldChatCutoverRows([
      row({
        database_now: "2026-08-25 00:02:00+00",
        activated_at: "2026-08-25 00:01:00+00",
        activated_candidate_sha: "a".repeat(40),
        activated_migration_sha256: "b".repeat(64),
        activated_explore_bundle_sha256: "c".repeat(64),
        activated_insight_bundle_sha256: "d".repeat(64),
        status: "active",
      }),
    ])
  );
});
