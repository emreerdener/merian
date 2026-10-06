import {
  assert,
  assertEquals,
  assertStringIncludes,
  assertThrows,
} from "@std/assert";
import { parsePreparedInsightChatContext } from "../insight-chat/preparedContext.ts";
import { parseStoredInsightChatContext } from "../insight-chat/storedContext.ts";
import {
  buildImmutableChatSystemInstruction,
  buildImmutableChatUserPrompt,
  immutableChatSemantics,
} from "../insight-chat/immutableContextPrompt.ts";
import {
  fixtureSpeciesID,
  savedIdentityFixture,
} from "./primaryIdentityTestHelpers.ts";
import { geminiMetricProvenance } from "./identificationMetricsTestFixtures.ts";
const owner = "00000000-0000-4000-8000-000000000001";
const scanID = "00000000-0000-4000-8000-000000000002";
const ticket = {
  analysis_id: "00000000-0000-4000-8000-000000000003",
  state_revision: 4,
  review_revision: 0,
};
const dictionary = {
  id: fixtureSpeciesID,
  scientific_name: "Fixtureus species",
  common_names: { en: "Fixture" },
  alternative_common_names: [],
  similar_species: [],
  group_tags: [],
};
function prepared(patch: Record<string, unknown> = {}) {
  return parsePreparedInsightChatContext({
    context_version: 1,
    source_kind: "analysis_history_v1",
    displayed_ticket: ticket,
    scan_context: {
      ...savedIdentityFixture(),
      ai_identification_review: null,
      user_observation_context: null,
      extracted_visual_traits: [],
      colors: [],
      ecological_interactions: [],
      species_dictionary: null,
      confirmed_species: null,
      ...patch,
    },
  }, { ownerId: owner, scanId: scanID, displayedTicket: ticket });
}
Deno.test("immutable primary semantics preserve null alternatives and reject malformed ranks", () => {
  assert(immutableChatSemantics(prepared()).eligible);
  assertThrows(
    () => immutableChatSemantics(prepared({ candidates: [] })),
    Error,
    "field_chat_context_unavailable",
  );
  assert(
    immutableChatSemantics(
      prepared({
        ...savedIdentityFixture("species"),
        candidates: [{ taxon_rank: "species", scientific_name: "Alternative" }],
      }),
    ).eligible,
  );
  for (const candidate of [{}, { taxon_rank: "genus" }]) {
    assertThrows(() =>
      immutableChatSemantics(
        prepared({
          ...savedIdentityFixture("species"),
          candidates: [candidate],
        }),
      )
    );
  }
});
Deno.test("immutable eligibility retains human, nonbiological and unresolved legacy rules", () => {
  const legacy = {
    primary_identification: null,
    identification_provenance: null,
    species_id: fixtureSpeciesID,
    species_dictionary: dictionary,
  };
  assert(immutableChatSemantics(prepared(legacy)).eligible);
  for (
    const name of ["Human", "Homo sapiens", "Unknown", "No wildlife detected"]
  ) {
    assert(
      !immutableChatSemantics(
        prepared({
          ...legacy,
          species_dictionary: { ...dictionary, scientific_name: name },
        }),
      ).eligible,
    );
  }
  assert(
    !immutableChatSemantics(
      prepared({ ...legacy, user_identification_override: " HUMAN " }),
    ).eligible,
  );
  assert(
    !immutableChatSemantics(
      prepared({ ...legacy, is_biological_subject: false }),
    ).eligible,
  );
  assert(
    !immutableChatSemantics(prepared({ ...legacy, species_dictionary: null }))
      .eligible,
  );
  assertThrows(
    () =>
      buildImmutableChatSystemInstruction(
        prepared({ ...legacy, species_dictionary: null }),
      ),
    Error,
    "field_chat_subject_ineligible",
  );
});
Deno.test("missing historical encounter stays unavailable and prompts omit operational authority/config", () => {
  const context = prepared({
    user_observation_context: { free_text: "Explicit observation" },
    ai_reasoning: "Original reasoning",
  });
  const semantic = immutableChatSemantics(context);
  assertEquals(semantic.data.encounter.timestamp, "Unavailable");
  assertEquals(semantic.data.encounter.weather_condition, "Unavailable");
  const prompt = buildImmutableChatSystemInstruction(context);
  assertStringIncludes(prompt, "Original reasoning");
  assertStringIncludes(prompt, "Explicit observation");
  for (
    const forbidden of [
      owner,
      scanID,
      ticket.analysis_id,
      "state_revision",
      "review_revision",
      "gpt-6-sol",
      "openai_photo_v1",
      "max_output_tokens",
      "synthetic_primary_fixture_v1",
      "species_id",
    ]
  ) assert(!prompt.includes(forbidden), forbidden);
  assert(!("conversation_prefix" in context));
});
Deno.test("scores use the immutable original-source decision; descriptions survive", () => {
  const base = {
    primary_identification: null,
    identification_provenance: geminiMetricProvenance(),
    inference_tier: "flash",
    species_id: fixtureSpeciesID,
    species_dictionary: dictionary,
    ai_confidence_score: 0.87123,
    candidates: [{
      scientific_name: "Alternative",
      confidence_score: 0.81234,
      distinguishing_feature: "Pale leaves",
    }],
  };
  for (const patch of [{}, { metrics_qualified: false }]) {
    const context = prepared({ ...base, ...patch });
    const semantic = immutableChatSemantics(context);
    assert(!semantic.metricsQualified);
    const prompt = buildImmutableChatSystemInstruction(context);
    assertStringIncludes(prompt, "Alternative");
    assertStringIncludes(prompt, "Pale leaves");
    assert(!prompt.includes("0.87123"));
    assert(!prompt.includes("0.81234"));
  }
  const qualified = prepared({ ...base, metrics_qualified: true });
  assert(immutableChatSemantics(qualified).metricsQualified);
  assertStringIncludes(
    buildImmutableChatSystemInstruction(qualified),
    "0.87123",
  );
  assertStringIncludes(
    buildImmutableChatSystemInstruction(qualified),
    "0.81234",
  );
  // Stored qualification is authoritative, even if runtime compatibility
  // policy later differs; no requalification of sanitized metadata on replay.
  assert(
    immutableChatSemantics(prepared({ metrics_qualified: true }))
      .metricsQualified,
  );
  assert(
    immutableChatSemantics(
      prepared({
        ...base,
        identification_provenance: null,
        metrics_qualified: true,
      }),
    ).metricsQualified,
  );
});
Deno.test("rejected and community authority remain distinct without leaking operation identifiers", () => {
  const review = {
    version: 1,
    revision: 1,
    state: "ai_rejected",
    origin_scan_id: scanID,
    origin_identification: { scientific_name: "Fixtureus", common_name: null },
    operation_id: owner,
    operation_digest: "a".repeat(32),
    community: null,
  };
  const rejected = prepared({ ai_identification_review: review });
  assert(immutableChatSemantics(rejected).eligible);
  assert(immutableChatSemantics(rejected).data.identification.pending_review);
  const community = prepared({
    ai_identification_review: {
      ...review,
      state: "clear",
      community: {
        request_id: owner,
        rank: "species",
        scientific_name: "Resolved species",
        common_name: "Resolved",
        species_id: fixtureSpeciesID,
      },
    },
    confirmed_species: dictionary,
  });
  assert(
    immutableChatSemantics(community).data.identification.verified_taxonomy,
  );
  const prompt = buildImmutableChatSystemInstruction(community);
  for (
    const forbidden of [
      owner,
      scanID,
      fixtureSpeciesID,
      "operation_digest",
      "a".repeat(32),
    ]
  ) assert(!prompt.includes(forbidden), forbidden);
  assertStringIncludes(prompt, "Resolved species");
});
Deno.test("stored prompt uses exact original ordered prefix and question without invented DB messages", () => {
  const context = prepared();
  const stored = parseStoredInsightChatContext({
    ...context,
    conversation_prefix: [
      { role: "assistant", text: "  First\nline  " },
      { role: "user", text: "Second" },
    ],
  }, ticket);
  assertEquals(
    buildImmutableChatUserPrompt(stored, "Exact\nquestion"),
    "[CHAT HISTORY]\nNaturebook:   First\nline  \nUser: Second\n\n[CURRENT USER QUESTION]\nExact\nquestion",
  );
});
