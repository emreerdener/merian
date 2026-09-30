import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  identificationResultContract,
  parseIdentifySuccessEnvelope,
  PRIMARY_IDENTIFICATION_SCHEMA,
} from "../identify/contract.ts";
import { normalizeSolPhotoPrimaryDraft } from "./openaiSolPrimaryNormalization.ts";
import type { PrimaryResolution } from "./openaiSolPrimaryContract.ts";
import {
  solPrimaryAlternativeFixture,
  solPrimaryDraftFixture,
} from "./testing/openaiSolPrimaryFixtures.ts";

const context = {
  hasVisualEvidence: true,
  hasAudioEvidence: false,
  hasInvasiveLocationContext: false,
  confidencePolicy: { kind: "unqualified" as const },
};
const normalize = (value: unknown) =>
  normalizeSolPhotoPrimaryDraft(value, context);

for (
  const resolution of [
    "species",
    "genus",
    "family",
    "unresolved_biological",
    "non_biological",
  ] as const
) {
  Deno.test(`explicit-primary ${resolution} preserves the declared answer, explanation and unqualified score`, () => {
    const value = solPrimaryDraftFixture(resolution);
    const original = structuredClone(value);
    const result = normalize(value);
    assertEquals(result.primary, {
      version: 1,
      resolution,
      scientific_name: value.scientific_name,
      common_name: value.common_name,
    });
    assertEquals(
      result.identification.scientific_name,
      result.primary.scientific_name,
    );
    assertEquals(result.identification.common_name, result.primary.common_name);
    assertEquals(result.identification.ai_reasoning, value.ai_reasoning);
    assertEquals(
      result.identification.confidence_score,
      value.confidence_score,
    );
    assertEquals(
      result.identification.candidates,
      resolution === "species" ? [] : null,
    );
    assertEquals(result.clientCandidates, resolution === "species" ? [] : null);
    assertEquals(result.identification.pet_identification, null);
    assert(!("resolution" in result.identification));
    assert(!("identification_provenance" in result.identification));
    assertEquals(value, original);
    assert(Object.isFrozen(result.primary));
  });
}

Deno.test("primary normalization rejects contradictory biological flags, missing names and species effects before normalization can hide them", () => {
  for (
    const resolution of [
      "species",
      "genus",
      "family",
      "unresolved_biological",
      "non_biological",
    ] as const
  ) {
    const draft = solPrimaryDraftFixture(resolution);
    assertThrows(() =>
      normalize({
        ...draft,
        is_biological_subject: !draft.is_biological_subject,
      })
    );
    if (["species", "genus", "family"].includes(resolution)) {
      for (const scientific_name of [null, "", "   ", "Syntheticus\nexample"]) {
        assertThrows(() => normalize({ ...draft, scientific_name }));
      }
    } else if (resolution === "unresolved_biological") {
      assertThrows(() =>
        normalize({ ...draft, scientific_name: "Syntheticus" })
      );
    }
    if (resolution !== "species") {
      assertThrows(() => normalize({ ...draft, candidates: [] }));
      assertThrows(() =>
        normalize({ ...draft, candidates: [solPrimaryAlternativeFixture()] })
      );
      assertThrows(() => normalize({ ...draft, pet_identification: pet }));
    }
  }
});

const pet = {
  species_group: "dog",
  label: "Synthetic Breed",
  label_type: "breed",
  confidence_score: 0.9,
  evidence: ["Invented test trait"],
};

Deno.test("eligible dog/cat canonicalization preserves the established species convention and cannot relabel a broader answer", () => {
  for (
    const [scientific_name, common_name, expected, species_group] of [
      ["Canis familiaris", "Dog", "Canis lupus familiaris", "dog"],
      ["Canis lupus familiaris", "Dog", "Canis lupus familiaris", "dog"],
      ["Felis silvestris catus", "Cat", "Felis catus", "cat"],
    ]
  ) {
    const result = normalize({
      ...solPrimaryDraftFixture(),
      scientific_name,
      common_name,
      pet_identification: { ...pet, species_group },
    });
    assertEquals(result.primary.scientific_name, expected);
    assertEquals(result.primary.resolution, "species");
    assertEquals(
      result.identification.pet_identification?.species_group,
      species_group,
    );
  }
  assertThrows(() =>
    normalize({
      ...solPrimaryDraftFixture("genus"),
      scientific_name: "Canis familiaris",
      common_name: "Dog",
    })
  );
});

Deno.test("hybrid/cultivar/marked infraspecific names fail instead of being shortened into supported taxa", () => {
  for (
    const scientific_name of [
      "Syntheticus × example",
      "× Syntheticus",
      "Syntheticus x example",
      "Syntheticus example var. minor",
      "Syntheticus example subsp. minor",
      "Syntheticus 'Cultivar'",
      "Syntheticus ‘Cultivar’",
    ]
  ) {
    assertThrows(() =>
      normalize({ ...solPrimaryDraftFixture(), scientific_name })
    );
    assertThrows(() =>
      normalize({
        ...solPrimaryDraftFixture(),
        candidates: [{ ...solPrimaryAlternativeFixture(), scientific_name }],
      })
    );
  }
});

Deno.test("processed-material demotion updates explicit resolution and removes candidates/pet detail without a second request", () => {
  const result = normalize({
    ...solPrimaryDraftFixture(),
    scientific_name: "Ovis aries",
    common_name: "Wool Rug",
    extracted_visual_traits: [
      "woven wool",
      "flat textile",
      "manufactured edges",
    ],
    ai_reasoning: "A manufactured textile made from processed wool.",
    candidates: [solPrimaryAlternativeFixture()],
  });
  assertEquals(result.primary, {
    version: 1,
    resolution: "non_biological",
    scientific_name: null,
    common_name: "Wool Rug",
  });
  assertEquals(result.identification.is_biological_subject, false);
  assertEquals(result.identification.is_live_capture, false);
  assertEquals(result.identification.candidates, null);
  assertEquals(result.clientCandidates, null);
  assertEquals(result.identification.pet_identification, null);
  assertEquals(result.diagnostics.map((d) => d.event), [
    "processed_material_demoted",
  ]);
});

Deno.test("uncertainty qualifiers never become explicit primary or alternative species claims", () => {
  for (const token of ["sp.", "spp.", "cf.", "aff.", "SP.", "CF."]) {
    for (
      const scientific_name of [
        `Syntheticus ${token}`,
        `Syntheticus ${token} example`,
        `${token} Syntheticus example`,
      ]
    ) {
      assertThrows(() =>
        normalize({ ...solPrimaryDraftFixture(), scientific_name })
      );
      assertThrows(() =>
        normalize({
          ...solPrimaryDraftFixture(),
          candidates: [{ ...solPrimaryAlternativeFixture(), scientific_name }],
        })
      );
    }
  }
});

Deno.test("preserved specimens stay biological; minerals retain names; unresolved null labels stay null", () => {
  const specimen = normalize({
    ...solPrimaryDraftFixture(),
    common_name: "Preserved Specimen",
    is_live_capture: false,
  });
  assertEquals(specimen.primary.resolution, "species");
  assertEquals(
    normalize(solPrimaryDraftFixture("non_biological")).primary.scientific_name,
    "Quartz",
  );
  const unknown = normalize({
    ...solPrimaryDraftFixture("unresolved_biological"),
    common_name: null,
  });
  assertEquals(unknown.primary.common_name, null);
  const unnamed = normalize({
    ...solPrimaryDraftFixture("non_biological"),
    scientific_name: null,
    common_name: null,
  });
  assertEquals(unnamed.primary.scientific_name, null);
});

Deno.test("explicit species alternatives keep their validated rank through existing name sanitation", () => {
  const result = normalize({
    ...solPrimaryDraftFixture(),
    candidates: [{
      ...solPrimaryAlternativeFixture(),
      scientific_name: "Syntheticus secunda L.",
    }],
  });
  assertEquals(
    result.identification.candidates?.[0].scientific_name,
    "Syntheticus secunda",
  );
  assertEquals(result.identification.candidates?.[0].taxon_rank, "species");
  assertEquals(result.clientCandidates, result.identification.candidates);
});

Deno.test("normalization cannot acquire audio, tier thresholds or nonvisual semantics", () => {
  for (
    const change of [
      { hasVisualEvidence: false },
      { hasAudioEvidence: true },
      {
        confidencePolicy: {
          kind: "diagnostic_threshold" as const,
          threshold: 0.7,
        },
      },
    ]
  ) {
    assertThrows(() =>
      normalizeSolPhotoPrimaryDraft(solPrimaryDraftFixture(), {
        ...context,
        ...change,
      })
    );
  }
});

// Invented wire fixture, not emitted by the candidate or any admitted producer.
function envelope(resolution: PrimaryResolution) {
  const result = normalize(solPrimaryDraftFixture(resolution));
  return {
    success: true,
    data: {
      ...result.identification,
      scan_id: "synthetic-contract-fixture",
      colors: [],
      estimated_size_cm: null,
      inference_tier: "flash",
      primary_identification: result.primary,
      is_new_to_merian_dictionary: false,
      identification_provenance: {
        version: 2,
        provider: "openai",
        binding: "synthetic_primary_fixture_v1",
        model: "gpt-6-sol",
        variant: "multimodal",
        operation: "scan_identification",
        policy_version: 1,
        prompt: "synthetic_primary_fixture_v1",
        schema: PRIMARY_IDENTIFICATION_SCHEMA,
        confidence: "openai_unqualified_v1",
        diagnostic_trigger: null,
        prompt_diagnostic_trigger: null,
        safety: "openai_photo_moderation_v1",
        timeout_ms: 90000,
        generation: {
          max_output_tokens: 8192,
          reasoning_effort: "low",
          image_detail: "high",
        },
      },
    },
  };
}

Deno.test("normalized explicit results satisfy the reserved wire boundary, including required snapshot and non-species enrichment rejection", () => {
  for (
    const resolution of [
      "species",
      "genus",
      "family",
      "unresolved_biological",
      "non_biological",
    ] as const
  ) {
    const value = envelope(resolution);
    assertEquals(
      parseIdentifySuccessEnvelope(value).data.primary_identification,
      value.data.primary_identification,
    );
    assertEquals(
      identificationResultContract(value.data.identification_provenance.schema),
      "primary_v1",
    );
    const { primary_identification: _snapshot, ...without } = value.data;
    assertThrows(() =>
      parseIdentifySuccessEnvelope({ success: true, data: without })
    );
    assertThrows(() =>
      parseIdentifySuccessEnvelope({
        success: true,
        data: { ...value.data, common_name: "Contradictory" },
      })
    );
    if (resolution !== "species") {
      assertThrows(() =>
        parseIdentifySuccessEnvelope({
          success: true,
          data: { ...value.data, gbif_taxon_key: "1234" },
        })
      );
    }
  }
  const family = envelope("family");
  assertThrows(() =>
    parseIdentifySuccessEnvelope({
      success: true,
      data: { ...family.data, taxonomy: { genus: "Syntheticus" } },
    })
  );
});
