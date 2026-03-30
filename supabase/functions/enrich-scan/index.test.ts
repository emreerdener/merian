// supabase/functions/enrich-scan/index.test.ts
//
// Unit tests for enrich-scan business logic that does not require a live
// Supabase client. All Postgres interactions are replaced with inline stubs.

import { assertEquals, assertExists } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { LookalikeSummary } from "./types.ts";
import { SimilarSpeciesEntry } from "../_shared/biology.ts";

// ---------------------------------------------------------------------------
// hasLookalikes gate logic
// ---------------------------------------------------------------------------

function hasLookalikes(
  lookalikes: LookalikeSummary[],
  flashAttempted: boolean,
): boolean {
  return lookalikes.some((l) => l.common_name !== null) || flashAttempted;
}

Deno.test("hasLookalikes — returns true when at least one common_name is non-null", () => {
  const lookalikes: LookalikeSummary[] = [
    { scientific_name: "Procyon cancrivorus", common_name: "Crab-eating Raccoon", reference_image_url: null, iucn_red_list_status: null },
    { scientific_name: "Bassariscus astutus", common_name: null, reference_image_url: null, iucn_red_list_status: null },
  ];
  assertEquals(hasLookalikes(lookalikes, false), true);
});

Deno.test("hasLookalikes — returns false when all common_names are null and flash not attempted", () => {
  // This is the migration-path scenario: join table populated before common-name back-fill.
  // Flash must run to back-fill names.
  const lookalikes: LookalikeSummary[] = [
    { scientific_name: "Procyon cancrivorus", common_name: null, reference_image_url: null, iucn_red_list_status: null },
    { scientific_name: "Bassariscus astutus", common_name: null, reference_image_url: null, iucn_red_list_status: null },
  ];
  assertEquals(hasLookalikes(lookalikes, false), false);
});

Deno.test("hasLookalikes — returns true when all common_names are null but lookalikes_flash_attempted is true", () => {
  // Species whose lookalikes are all legitimately obscure (no English common name).
  // Flash has already been called — the flag prevents infinite re-calls.
  const lookalikes: LookalikeSummary[] = [
    { scientific_name: "Procyon cancrivorus", common_name: null, reference_image_url: null, iucn_red_list_status: null },
  ];
  assertEquals(hasLookalikes(lookalikes, true), true);
});

Deno.test("hasLookalikes — returns false for empty lookalikes array when flash not attempted", () => {
  assertEquals(hasLookalikes([], false), false);
});

Deno.test("hasLookalikes — returns true for empty lookalikes array when flash already attempted", () => {
  assertEquals(hasLookalikes([], true), true);
});

// ---------------------------------------------------------------------------
// resolveLookalikesToJoinTable fallback: Flash stubs for unmatched species
// ---------------------------------------------------------------------------

// Inline stub of the unmatched-species logic from resolveLookalikesToJoinTable
// (the part that runs when species are not in species_dictionary).
function buildUnmatchedStubs(
  entries: SimilarSpeciesEntry[],
  matchedNames: Set<string>,
): LookalikeSummary[] {
  return entries
    .filter((e) => !matchedNames.has(e.scientific_name))
    .map((e) => ({
      scientific_name: e.scientific_name,
      common_name: e.common_name,
      reference_image_url: null,
      iucn_red_list_status: null,
    }));
}

Deno.test("unmatched species return Flash common_name in stub — not silently dropped", () => {
  const entries: SimilarSpeciesEntry[] = [
    { scientific_name: "Rare obscura", common_name: "Obscure Species" },
    { scientific_name: "Procyon lotor", common_name: "Raccoon" },
  ];
  // Only Procyon lotor is in the dictionary
  const matched = new Set(["Procyon lotor"]);
  const stubs = buildUnmatchedStubs(entries, matched);

  assertEquals(stubs.length, 1);
  assertEquals(stubs[0].scientific_name, "Rare obscura");
  assertEquals(stubs[0].common_name, "Obscure Species", "Flash-generated common_name must be preserved in stub");
  assertEquals(stubs[0].reference_image_url, null, "Unmatched stubs have no reference image");
  assertEquals(stubs[0].iucn_red_list_status, null);
});

Deno.test("unmatched species with null Flash common_name produce null stub — not empty string", () => {
  const entries: SimilarSpeciesEntry[] = [
    { scientific_name: "Truly obscura", common_name: null },
  ];
  const matched = new Set<string>();
  const stubs = buildUnmatchedStubs(entries, matched);

  assertEquals(stubs.length, 1);
  assertEquals(stubs[0].common_name, null, "null common_name from Flash must remain null in stub");
});

Deno.test("all species matched — unmatched stubs list is empty", () => {
  const entries: SimilarSpeciesEntry[] = [
    { scientific_name: "Procyon lotor", common_name: "Raccoon" },
  ];
  const matched = new Set(["Procyon lotor"]);
  const stubs = buildUnmatchedStubs(entries, matched);
  assertEquals(stubs.length, 0);
});

// ---------------------------------------------------------------------------
// back-fill filter: merge_common_name_en candidates
// ---------------------------------------------------------------------------

// Inline stub of the backfill filter logic from resolveLookalikesToJoinTable.
function backfillCandidates(
  typed: { scientific_name: string; common_names: Record<string, string> | null }[],
  entryByName: Map<string, SimilarSpeciesEntry>,
): string[] {
  return typed
    .filter((m) => {
      const flashName = entryByName.get(m.scientific_name)?.common_name ?? null;
      if (!flashName) return false;
      const hasEn = m.common_names != null && m.common_names["en"] != null;
      return !hasEn;
    })
    .map((m) => m.scientific_name);
}

Deno.test("back-fill fires for species with null common_names", () => {
  const typed = [{ scientific_name: "Procyon cancrivorus", common_names: null }];
  const map = new Map([["Procyon cancrivorus", { scientific_name: "Procyon cancrivorus", common_name: "Crab-eating Raccoon" }]]);
  const candidates = backfillCandidates(typed, map);
  assertEquals(candidates, ["Procyon cancrivorus"]);
});

Deno.test("back-fill fires for species with partial locale — missing 'en' key", () => {
  const typed = [{ scientific_name: "Procyon cancrivorus", common_names: { fr: "Raton crabier" } }];
  const map = new Map([["Procyon cancrivorus", { scientific_name: "Procyon cancrivorus", common_name: "Crab-eating Raccoon" }]]);
  const candidates = backfillCandidates(typed, map as Map<string, SimilarSpeciesEntry>);
  assertEquals(candidates, ["Procyon cancrivorus"]);
});

Deno.test("back-fill skips species that already have 'en' key — authoritative data preserved", () => {
  const typed = [{ scientific_name: "Procyon lotor", common_names: { en: "Raccoon" } }];
  const map = new Map([["Procyon lotor", { scientific_name: "Procyon lotor", common_name: "Common Raccoon" }]]);
  const candidates = backfillCandidates(typed, map as Map<string, SimilarSpeciesEntry>);
  assertEquals(candidates.length, 0, "Species with existing 'en' key must not be overwritten");
});

Deno.test("back-fill skips species where Flash returned null common_name", () => {
  const typed = [{ scientific_name: "Rare obscura", common_names: null }];
  const map = new Map([["Rare obscura", { scientific_name: "Rare obscura", common_name: null }]]);
  const candidates = backfillCandidates(typed, map as Map<string, SimilarSpeciesEntry>);
  assertEquals(candidates.length, 0, "Null Flash common_name must not trigger a back-fill write");
});
