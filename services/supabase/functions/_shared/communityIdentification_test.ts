import { assertEquals, assertThrows } from "@std/assert";
import {
  normalizeCommunityBoolean,
  normalizeCommunityLocationSharing,
  normalizeCommunityNote,
  normalizeCommunityReasoning,
  normalizeCommunitySearchQuery,
  normalizeDisagreementMode,
} from "./communityIdentification.ts";

Deno.test("community identification note and reasoning trim empty text to null", () => {
  assertEquals(
    normalizeCommunityNote("  look at wing venation  "),
    "look at wing venation",
  );
  assertEquals(normalizeCommunityNote("   "), null);
  assertEquals(
    normalizeCommunityReasoning("\nnot enough detail\n"),
    "not enough detail",
  );
  assertEquals(normalizeCommunityReasoning(null), null);
});

Deno.test("community identification search query collapses spacing and enforces length", () => {
  assertEquals(
    normalizeCommunitySearchQuery("  red   tailed hawk "),
    "red tailed hawk",
  );

  assertThrows(
    () => normalizeCommunitySearchQuery("x"),
    Error,
    "query must be at least 2 characters",
  );
});

Deno.test("community identification location sharing accepts hidden alias", () => {
  assertEquals(normalizeCommunityLocationSharing("open"), "open");
  assertEquals(normalizeCommunityLocationSharing("hidden"), "private");
  assertEquals(normalizeCommunityLocationSharing(undefined), null);
});

Deno.test("community identification disagreement mode defaults and validates", () => {
  assertEquals(normalizeDisagreementMode(undefined), "implicit_support");
  assertEquals(normalizeDisagreementMode("maverick"), "maverick");

  assertThrows(
    () => normalizeDisagreementMode("override"),
    Error,
    "disagreement_mode must be implicit_support",
  );
});

Deno.test("community identification boolean parser rejects non-booleans", () => {
  assertEquals(
    normalizeCommunityBoolean(undefined, "is_genus_best_possible"),
    false,
  );
  assertEquals(normalizeCommunityBoolean(true, "is_genus_best_possible"), true);

  assertThrows(
    () => normalizeCommunityBoolean("true", "is_genus_best_possible"),
    Error,
    "is_genus_best_possible must be a boolean",
  );
});
