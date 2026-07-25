// _tests/enrichScanScope.test.ts
//
// Unit tests for enrich-scan scope routing, payload shaping, and the
// lookalikes_flash_attempted empty-array guard.
//
// All logic is inline-stubbed — no live Supabase client required.

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

// ---------------------------------------------------------------------------
// Inline stubs: types
// ---------------------------------------------------------------------------

interface LookalikeSummary {
  scientific_name: string;
  common_name: string | null;
  reference_image_url: string | null;
  iucn_red_list_status: string | null;
}

interface CachedSpeciesData {
  id: string;
  gbif_taxon_key: number | null;
  habitat_description: string | null;
  kingdom: string | null;
  phylum: string | null;
  class: string | null;
  order: string | null;
  family: string | null;
  genus: string | null;
  similar_species: string[] | null;
  lookalikes_flash_attempted: boolean;
}

interface EncyclopedicData {
  habitat_description: string;
  taxonomy: {
    kingdom: string;
    phylum: string;
    class: string;
    order: string;
    family: string;
    genus: string;
  };
  usage?: { totalTokenCount: number };
}

// ---------------------------------------------------------------------------
// Inline stubs: payload formatters (mirrors index.ts exactly)
// ---------------------------------------------------------------------------

function formatEnrichmentOnlyPayload(
  cachedSpecies: CachedSpeciesData | null,
  enrichmentResult: EncyclopedicData | null,
) {
  return {
    scope: "enrichment" as const,
    habitat_description: enrichmentResult?.habitat_description ??
      cachedSpecies?.habitat_description ??
      "No habitat data available.",
    gbif_taxon_key: cachedSpecies?.gbif_taxon_key,
    taxonomy: {
      kingdom: enrichmentResult?.taxonomy?.kingdom ?? cachedSpecies?.kingdom ??
        "Unknown",
      phylum: enrichmentResult?.taxonomy?.phylum ?? cachedSpecies?.phylum ??
        "Unknown",
      class: enrichmentResult?.taxonomy?.class ?? cachedSpecies?.class ??
        "Unknown",
      order: enrichmentResult?.taxonomy?.order ?? cachedSpecies?.order ??
        "Unknown",
      family: enrichmentResult?.taxonomy?.family ?? cachedSpecies?.family ??
        "Unknown",
      genus: enrichmentResult?.taxonomy?.genus ?? cachedSpecies?.genus ??
        "Unknown",
    },
  };
}

function formatLookalikesOnlyPayload(
  cachedSpecies: CachedSpeciesData | null,
  lookalikes: LookalikeSummary[],
) {
  const resolvedLookalikes: LookalikeSummary[] = lookalikes.length > 0
    ? lookalikes
    : (cachedSpecies?.similar_species ?? []).map((name) => ({
      scientific_name: name,
      common_name: null,
      reference_image_url: null,
      iucn_red_list_status: null,
    }));
  return {
    scope: "lookalikes" as const,
    similar_species: resolvedLookalikes.length > 0 ? resolvedLookalikes : null,
  };
}

// ---------------------------------------------------------------------------
// Inline stub: hasEnrichment / hasLookalikes gate logic (mirrors index.ts)
// ---------------------------------------------------------------------------

function hasEnrichment(cachedSpecies: CachedSpeciesData | null): boolean {
  return cachedSpecies?.habitat_description !== null &&
    cachedSpecies?.habitat_description !== undefined;
}

// Mirrors the lookalikes_flash_attempted write guard in index.ts:
//   if (resolveResult.persisted && lookalikes.length > 0) { ... }
// Both conditions must be true: the join table must have been written (persisted)
// AND lookalikes must be non-empty. A null-kingdom early-exit sets persisted=false,
// which must NOT lock the flag even when Flash returned non-empty lookalikes.
function shouldSetFlashAttempted(
  persisted: boolean,
  lookalikes: LookalikeSummary[],
): boolean {
  return persisted && lookalikes.length > 0;
}

// ---------------------------------------------------------------------------
// SCOPE ROUTING — formatEnrichmentOnlyPayload
// ---------------------------------------------------------------------------

Deno.test("enrichment scope — payload contains scope, habitat, gbif_taxon_key, taxonomy; NO similar_species", () => {
  const cached: CachedSpeciesData = {
    id: "abc",
    gbif_taxon_key: 12345,
    habitat_description: "Temperate forests",
    kingdom: "Plantae",
    phylum: "T",
    class: "T",
    order: "T",
    family: "T",
    genus: "Dahlia",
    similar_species: null,
    lookalikes_flash_attempted: false,
  };
  const payload = formatEnrichmentOnlyPayload(cached, null);

  assertEquals(payload.scope, "enrichment");
  assertExists(payload.habitat_description);
  assertExists(payload.gbif_taxon_key);
  assertExists(payload.taxonomy);
  assertEquals(
    (payload as Record<string, unknown>)["similar_species"],
    undefined,
  );
});

Deno.test("enrichment scope — Flash result takes priority over cached habitat", () => {
  const cached: CachedSpeciesData = {
    id: "abc",
    gbif_taxon_key: null,
    habitat_description: "Old cached habitat",
    kingdom: null,
    phylum: null,
    class: null,
    order: null,
    family: null,
    genus: null,
    similar_species: null,
    lookalikes_flash_attempted: false,
  };
  const enrichment: EncyclopedicData = {
    habitat_description: "Fresh Flash habitat",
    taxonomy: {
      kingdom: "Plantae",
      phylum: "P",
      class: "C",
      order: "O",
      family: "F",
      genus: "G",
    },
  };
  const payload = formatEnrichmentOnlyPayload(cached, enrichment);
  assertEquals(payload.habitat_description, "Fresh Flash habitat");
});

Deno.test("enrichment scope — fallback to 'No habitat data available.' when both are null", () => {
  const payload = formatEnrichmentOnlyPayload(null, null);
  assertEquals(payload.habitat_description, "No habitat data available.");
  assertEquals(payload.gbif_taxon_key, undefined);
});

Deno.test("enrichment scope — taxonomy falls back to cached values when enrichment is null", () => {
  const cached: CachedSpeciesData = {
    id: "abc",
    gbif_taxon_key: null,
    habitat_description: "Forest",
    kingdom: "Plantae",
    phylum: "P",
    class: "C",
    order: "O",
    family: "F",
    genus: "Dahlia",
    similar_species: null,
    lookalikes_flash_attempted: false,
  };
  const payload = formatEnrichmentOnlyPayload(cached, null);
  assertEquals(payload.taxonomy.kingdom, "Plantae");
  assertEquals(payload.taxonomy.genus, "Dahlia");
});

// ---------------------------------------------------------------------------
// SCOPE ROUTING — formatLookalikesOnlyPayload
// ---------------------------------------------------------------------------

Deno.test("lookalikes scope — payload contains scope and similar_species; NO habitat/taxonomy/gbif", () => {
  const lookalikes: LookalikeSummary[] = [
    {
      scientific_name: "Dahlia coccinea",
      common_name: "Scarlet Dahlia",
      reference_image_url: null,
      iucn_red_list_status: null,
    },
  ];
  const payload = formatLookalikesOnlyPayload(null, lookalikes);

  assertEquals(payload.scope, "lookalikes");
  assertExists(payload.similar_species);
  assertEquals(
    (payload as Record<string, unknown>)["habitat_description"],
    undefined,
  );
  assertEquals((payload as Record<string, unknown>)["taxonomy"], undefined);
});

Deno.test("lookalikes scope — returns null similar_species when join table is empty and no TEXT[] fallback", () => {
  const payload = formatLookalikesOnlyPayload(null, []);
  assertEquals(payload.similar_species, null);
});

Deno.test("lookalikes scope — falls back to TEXT[] names when join table is empty", () => {
  const cached: CachedSpeciesData = {
    id: "abc",
    gbif_taxon_key: null,
    habitat_description: null,
    kingdom: null,
    phylum: null,
    class: null,
    order: null,
    family: null,
    genus: null,
    similar_species: ["Dahlia coccinea", "Dahlia imperialis"],
    lookalikes_flash_attempted: false,
  };
  const payload = formatLookalikesOnlyPayload(cached, []);
  assertEquals(payload.similar_species?.length, 2);
  assertEquals(payload.similar_species?.[0].scientific_name, "Dahlia coccinea");
  assertEquals(
    payload.similar_species?.[0].common_name,
    null,
    "TEXT[] fallback has null common_name",
  );
});

Deno.test("lookalikes scope — join table entries take priority over TEXT[] fallback", () => {
  const cached: CachedSpeciesData = {
    id: "abc",
    gbif_taxon_key: null,
    habitat_description: null,
    kingdom: null,
    phylum: null,
    class: null,
    order: null,
    family: null,
    genus: null,
    similar_species: ["Old species"],
    lookalikes_flash_attempted: false,
  };
  const joinTableEntries: LookalikeSummary[] = [
    {
      scientific_name: "Dahlia coccinea",
      common_name: "Scarlet Dahlia",
      reference_image_url: "https://img",
      iucn_red_list_status: null,
    },
  ];
  const payload = formatLookalikesOnlyPayload(cached, joinTableEntries);
  assertEquals(payload.similar_species?.length, 1);
  assertEquals(payload.similar_species?.[0].scientific_name, "Dahlia coccinea");
  assertEquals(payload.similar_species?.[0].common_name, "Scarlet Dahlia");
});

// ---------------------------------------------------------------------------
// CACHE HIT GATES
// ---------------------------------------------------------------------------

Deno.test("enrichment cache hit — fires when habitat_description is present", () => {
  const cached: CachedSpeciesData = {
    id: "abc",
    gbif_taxon_key: 1,
    habitat_description: "Forests",
    kingdom: null,
    phylum: null,
    class: null,
    order: null,
    family: null,
    genus: null,
    similar_species: null,
    lookalikes_flash_attempted: false,
  };
  assertEquals(hasEnrichment(cached), true);
});

Deno.test("enrichment cache miss — fires when habitat_description is null", () => {
  const cached: CachedSpeciesData = {
    id: "abc",
    gbif_taxon_key: null,
    habitat_description: null,
    kingdom: null,
    phylum: null,
    class: null,
    order: null,
    family: null,
    genus: null,
    similar_species: null,
    lookalikes_flash_attempted: false,
  };
  assertEquals(hasEnrichment(cached), false);
});

Deno.test("enrichment cache miss — fires when cachedSpecies is null (species not in dictionary)", () => {
  assertEquals(hasEnrichment(null), false);
});

// ---------------------------------------------------------------------------
// lookalikes_flash_attempted EMPTY-ARRAY GUARD (the Dahlia bug fix)
// ---------------------------------------------------------------------------

Deno.test("flash_attempted guard — NOT set when Flash returns empty array (persisted=true)", () => {
  // This is the exact scenario that caused Dahlia's lookalikes to never appear:
  // Flash returned [] (JS truthy), the flag was set, permanently blocking retries.
  assertEquals(shouldSetFlashAttempted(true, []), false);
});

Deno.test("flash_attempted guard — NOT set when Flash returns empty array (persisted=false)", () => {
  assertEquals(shouldSetFlashAttempted(false, []), false);
});

Deno.test("flash_attempted guard — set when join table was written and lookalikes are non-empty", () => {
  const lookalikes: LookalikeSummary[] = [
    {
      scientific_name: "Dahlia coccinea",
      common_name: "Scarlet Dahlia",
      reference_image_url: null,
      iucn_red_list_status: null,
    },
  ];
  assertEquals(shouldSetFlashAttempted(true, lookalikes), true);
});

Deno.test("flash_attempted guard — set when lookalikes resolved but all common_names are null (obscure species)", () => {
  // Flash produced entries (species exist in dictionary) but none have a known English name.
  // The flag should still be set to prevent infinite re-calls.
  const lookalikes: LookalikeSummary[] = [
    {
      scientific_name: "Rare taxon A",
      common_name: null,
      reference_image_url: null,
      iucn_red_list_status: null,
    },
    {
      scientific_name: "Rare taxon B",
      common_name: null,
      reference_image_url: null,
      iucn_red_list_status: null,
    },
  ];
  assertEquals(shouldSetFlashAttempted(true, lookalikes), true);
});

Deno.test("flash_attempted guard — NOT set when persisted=false even with non-empty lookalikes (null-kingdom early-exit)", () => {
  // resolveLookalikesToJoinTable returns persisted=false when primaryKingdom is null —
  // the join table write is skipped entirely. The flag must NOT lock in this state
  // or the species can never be enriched once kingdom propagates via replication.
  const lookalikes: LookalikeSummary[] = [
    {
      scientific_name: "Some species",
      common_name: "Some Name",
      reference_image_url: null,
      iucn_red_list_status: null,
    },
  ];
  assertEquals(shouldSetFlashAttempted(false, lookalikes), false);
});

// ---------------------------------------------------------------------------
// SCOPE INDEPENDENCE — each scope returns only its own field set
// ---------------------------------------------------------------------------

Deno.test("enrichment and lookalikes payloads are disjoint field sets", () => {
  const enrichPayload = formatEnrichmentOnlyPayload(null, null) as Record<
    string,
    unknown
  >;
  const lookalikesPayload = formatLookalikesOnlyPayload(null, []) as Record<
    string,
    unknown
  >;

  // enrichment-only fields
  assertExists(enrichPayload["habitat_description"]);
  assertExists(enrichPayload["taxonomy"]);
  assertEquals(enrichPayload["similar_species"], undefined);

  // lookalikes-only fields — similar_species key exists (may be null) but habitat fields absent
  assertEquals("similar_species" in lookalikesPayload, true);
  assertEquals(lookalikesPayload["habitat_description"], undefined);
  assertEquals(lookalikesPayload["taxonomy"], undefined);
  assertEquals(lookalikesPayload["gbif_taxon_key"], undefined);
});
