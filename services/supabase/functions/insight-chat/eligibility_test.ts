import { assert, assertEquals } from "@std/assert";
import { isFieldChatEligibleScan } from "./eligibility.ts";
import type { ChatScanContext, SpeciesDictionaryContext } from "./types.ts";

function species(scientificName: string): SpeciesDictionaryContext {
  return {
    id: "00000000-0000-4000-8000-000000000003",
    scientific_name: scientificName,
    common_names: null,
    wikipedia_overview: null,
    habitat_description: null,
    hazard_type: null,
    kingdom: null,
    phylum: null,
    class: null,
    order: null,
    family: null,
    genus: null,
    iucn_red_list_status: null,
    alternative_common_names: null,
    similar_species: null,
    group_tags: null,
  };
}

function scan(
  overrides: Partial<ChatScanContext> = {},
): ChatScanContext {
  return {
    id: "00000000-0000-4000-8000-000000000001",
    user_id: "00000000-0000-4000-8000-000000000002",
    timestamp: "2026-08-17T12:00:00Z",
    gps_elevation: null,
    weather_condition: null,
    weather_temperature_f: null,
    semantic_location: null,
    current_month: null,
    time_of_day: null,
    depth_scale_text: null,
    ai_confidence_score: null,
    ai_reasoning: null,
    candidates: null,
    image_quality_score: null,
    blur_score: null,
    zoom_factor: null,
    ecology_type: null,
    colors: null,
    life_stage: null,
    reproductive_condition: null,
    estimated_size_cm: null,
    individual_count: null,
    ecological_interactions: null,
    sex: null,
    sex_confidence: null,
    sex_evidence: null,
    is_invasive: null,
    invasive_status_region: null,
    invasive_rationale: null,
    invasive_confidence: null,
    is_biological_subject: true,
    user_identification_override: null,
    user_confirmed_identification: false,
    user_review_state: "unreviewed",
    user_observation_context: null,
    confirmed_species_id: null,
    species_id: "00000000-0000-4000-8000-000000000003",
    confirmed_species: null,
    species_dictionary: species("Turdus migratorius"),
    ...overrides,
  };
}

Deno.test("Field Chat admits a resolved non-Human biological scan", () => {
  assert(isFieldChatEligibleScan(scan()));
});

Deno.test("Field Chat rejects non-biological and unresolved scans", () => {
  assertEquals(
    isFieldChatEligibleScan(scan({ is_biological_subject: false })),
    false,
  );
  assertEquals(
    isFieldChatEligibleScan(scan({
      species_id: null,
      species_dictionary: null,
    })),
    false,
  );
  for (
    const scientificName of [
      "Taxonomy Unavailable",
      "Unidentified Wildlife",
      "Unknown Subject",
    ]
  ) {
    assertEquals(
      isFieldChatEligibleScan(scan({
        species_dictionary: species(scientificName),
      })),
      false,
    );
  }
});

Deno.test("Field Chat rejects canonical and malformed Human identities", () => {
  for (const scientificName of ["Homo sapiens", "Homo sapien"]) {
    assertEquals(
      isFieldChatEligibleScan(scan({
        species_dictionary: species(scientificName),
      })),
      false,
    );
    assertEquals(
      isFieldChatEligibleScan(scan({
        user_identification_override: scientificName,
      })),
      false,
    );
  }

  for (const override of ["Human", "Human Being", "Person"]) {
    assertEquals(
      isFieldChatEligibleScan(scan({
        user_identification_override: override,
      })),
      false,
    );
  }
});

Deno.test("Field Chat uses the confirmed relation as the effective taxonomy", () => {
  assert(
    isFieldChatEligibleScan(scan({
      species_dictionary: species("Homo sapiens"),
      confirmed_species_id: "00000000-0000-4000-8000-000000000004",
      confirmed_species: [species("Turdus migratorius")],
      user_identification_override: "Turdus migratorius",
    })),
  );
});

Deno.test("Insight Chat endpoint checks eligibility before entitlement or actions", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const eligibility = source.indexOf("isFieldChatEligibleScan(scan)");
  const tier = source.indexOf("resolveTierForUser", eligibility);
  const action = source.indexOf('if (action === "delete")', eligibility);

  assert(eligibility >= 0);
  assert(tier > eligibility);
  assert(action > eligibility);
});
