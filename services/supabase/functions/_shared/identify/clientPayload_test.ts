import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";

import {
  hydratePayloadFromCachedSpecies,
  isNewToMerianDictionary,
} from "./clientPayload.ts";
import { CachedSpeciesRow, ClientPayload } from "./types.ts";

Deno.test("hydratePayloadFromCachedSpecies injects cached taxonomy and habitat fields", () => {
  const payload: ClientPayload = {
    scan_id: "scan-123",
    is_biological_subject: true,
    is_live_capture: true,
    scientific_name: "Danaus plexippus",
    common_name: "Monarch",
    confidence_score: 0.97,
    blur_score: 0.1,
    colors: [],
    candidates: null,
    estimated_size_cm: null,
    image_quality: {
      sharpness: 9,
      framing: 8,
      diagnostic_utility: 9,
      overall_score: 90,
    },
    pet_identification: null,
    ai_reasoning: "Visible wing veins and orange-black pattern.",
    extracted_visual_traits: ["orange wings", "black veins", "white spots"],
    insight_data: {
      ai_reasoning: "Visible wing veins and orange-black pattern.",
      hazard_type: "none",
    },
    inference_tier: "flash",
  };

  const cachedSpecies: CachedSpeciesRow = {
    id: "species-123",
    common_names: { en: "Monarch Butterfly" },
    alternative_common_names: ["Monarch Butterfly", "Milkweed Butterfly"],
    kingdom: "Animalia",
    phylum: "Arthropoda",
    class: "Insecta",
    order: "Lepidoptera",
    family: "Nymphalidae",
    genus: "Danaus",
    wikipedia_overview: "A migratory milkweed butterfly.",
    hazard_type: "none",
    reference_image_url: "https://example.com/reference.webp",
    wikipedia_url: "https://example.com/wiki",
    iucn_red_list_status: "least_concern",
    habitat_description: "Frequently seen in meadows and milkweed patches.",
    gbif_taxon_key: 1890490,
    group_tags: ["animal", "insect", "butterfly"],
  };

  const hydrated = hydratePayloadFromCachedSpecies(payload, cachedSpecies);

  assertEquals(hydrated.common_name, "Monarch Butterfly");
  assertEquals(hydrated.alternative_common_names, ["Milkweed Butterfly"]);
  assertEquals(
    hydrated.reference_image_url,
    "https://example.com/reference.webp",
  );
  assertEquals(hydrated.wikipedia_url, "https://example.com/wiki");
  assertEquals(hydrated.wikipedia_overview, "A migratory milkweed butterfly.");
  assertEquals(hydrated.taxonomy?.genus, "Danaus");
  assertEquals(hydrated.iucn_red_list_status, "least_concern");
  assertEquals(hydrated.insight_data?.ai_reasoning, payload.ai_reasoning);
  assertEquals(hydrated.insight_data?.hazard_type, "none");
  assertEquals(
    hydrated.species_insights?.habitat_description,
    "Frequently seen in meadows and milkweed patches.",
  );
  assertEquals(hydrated.gbif_taxon_key, 1890490);
  assertEquals(hydrated.group_tags, ["animal", "insect", "butterfly"]);
});

Deno.test("hydratePayloadFromCachedSpecies falls back safely when optional cached fields are missing", () => {
  const payload: ClientPayload = {
    scan_id: "scan-456",
    is_biological_subject: true,
    is_live_capture: false,
    scientific_name: "Unknownus examplea",
    common_name: "Example Species",
    confidence_score: 0.88,
    blur_score: 0.2,
    colors: [],
    candidates: null,
    estimated_size_cm: null,
    image_quality: {
      sharpness: 8,
      framing: 7,
      diagnostic_utility: 8,
      overall_score: 80,
    },
    pet_identification: null,
    ai_reasoning: "Pattern and silhouette match the cached species.",
    extracted_visual_traits: ["patterned body"],
    insight_data: {
      ai_reasoning: "Pattern and silhouette match the cached species.",
      hazard_type: "none",
    },
    inference_tier: "pro",
  };

  const cachedSpecies: CachedSpeciesRow = {
    id: "species-456",
    common_names: null,
    alternative_common_names: null,
    kingdom: null,
    phylum: null,
    class: null,
    order: null,
    family: null,
    genus: null,
    wikipedia_overview: null,
    hazard_type: null,
    reference_image_url: null,
    wikipedia_url: null,
    iucn_red_list_status: null,
    habitat_description: null,
    gbif_taxon_key: null,
    group_tags: null,
  };

  const hydrated = hydratePayloadFromCachedSpecies(payload, cachedSpecies);

  assertEquals(hydrated.common_name, "Example Species");
  assertEquals(hydrated.alternative_common_names, null);
  assertEquals(hydrated.taxonomy?.kingdom, "Unknown");
  assertEquals(hydrated.iucn_red_list_status, "not_evaluated");
  assertEquals(hydrated.insight_data?.ai_reasoning, payload.ai_reasoning);
  assertEquals(hydrated.insight_data?.hazard_type, "none");
  assertEquals(hydrated.species_insights, undefined);
  assertEquals(hydrated.group_tags, undefined);
  assertEquals(hydrated.gbif_taxon_key, undefined);
});

Deno.test("isNewToMerianDictionary is true only for biological dictionary misses", () => {
  const cachedSpecies: CachedSpeciesRow = {
    id: "species-existing",
    common_names: null,
    alternative_common_names: null,
    kingdom: null,
    phylum: null,
    class: null,
    order: null,
    family: null,
    genus: null,
    wikipedia_overview: null,
    hazard_type: null,
    reference_image_url: null,
    wikipedia_url: null,
    iucn_red_list_status: null,
    habitat_description: null,
    gbif_taxon_key: null,
    group_tags: null,
  };

  assertEquals(isNewToMerianDictionary(true, null), true);
  assertEquals(isNewToMerianDictionary(true, cachedSpecies), false);
  assertEquals(isNewToMerianDictionary(false, null), false);
});

Deno.test("hydratePayloadFromCachedSpecies normalizes unsupported cached hazards", () => {
  const payload: ClientPayload = {
    scan_id: "scan-hazard",
    is_biological_subject: true,
    is_live_capture: true,
    scientific_name: "Example species",
    common_name: "Example",
    confidence_score: 0.9,
    blur_score: 0.1,
    colors: [],
    candidates: null,
    estimated_size_cm: null,
    image_quality: {
      sharpness: 9,
      framing: 9,
      diagnostic_utility: 9,
      overall_score: 90,
    },
    pet_identification: null,
    ai_reasoning: "Visible diagnostic traits support the identification.",
    extracted_visual_traits: ["diagnostic trait"],
    inference_tier: "flash",
  };
  const cachedSpecies: CachedSpeciesRow = {
    id: "species-hazard",
    common_names: null,
    alternative_common_names: null,
    kingdom: null,
    phylum: null,
    class: null,
    order: null,
    family: null,
    genus: null,
    wikipedia_overview: null,
    hazard_type: "legacy_unsafe_value",
    reference_image_url: null,
    wikipedia_url: null,
    iucn_red_list_status: null,
    habitat_description: null,
    gbif_taxon_key: null,
    group_tags: null,
  };

  const hydrated = hydratePayloadFromCachedSpecies(payload, cachedSpecies);

  assertEquals(hydrated.insight_data?.hazard_type, "none");
});
