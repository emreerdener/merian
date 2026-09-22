import { assertEquals, assertThrows } from "@std/assert";
import { ContractValueError } from "./contract.ts";
import {
  type IdentificationNormalizationContext,
  normalizeIdentification,
} from "./normalizeIdentification.ts";

const context: IdentificationNormalizationContext = {
  hasVisualEvidence: true,
  hasAudioEvidence: false,
  hasInvasiveLocationContext: false,
  inferenceTier: "flash",
};
const candidate = {
  scientific_name: "cf. Danaus gilippus",
  confidence_score: 0.6,
  distinguishing_feature: "Synthetic alternative wing pattern.",
};
const draft = {
  is_biological_subject: true,
  is_live_capture: true,
  scientific_name: "  danaus  Plexippus L. ",
  common_name: "Monarch",
  confidence_score: 0.88,
  ai_reasoning: "Synthetic fixture with a contrasting wing pattern.",
  extracted_visual_traits: ["synthetic orange wings"],
  candidates: [candidate],
  image_quality: {
    sharpness: 10,
    framing: 10,
    diagnostic_utility: 10,
    overall_score: 100,
  },
};
const unavailable =
  "Location context was unavailable, so Naturebook could not make a region-specific invasive assessment.";

Deno.test("normalization preserves the complete pre-hydration result across both tiers and six input forms", () => {
  for (const inferenceTier of ["flash", "pro"] as const) {
    for (
      const mode of [
        { name: "photos", visual: true, audio: false },
        { name: "description", visual: false, audio: false },
        { name: "audio", visual: false, audio: true },
        { name: "frames", visual: true, audio: false },
        { name: "frames_audio", visual: true, audio: true },
        { name: "photos_audio", visual: true, audio: true },
      ]
    ) {
      const audioOnly = mode.audio && !mode.visual;
      const input = {
        ...draft,
        ...(audioOnly ? { audio_subject_type: "identified_non_human" } : {}),
        ignored_provider_field: "must not survive parsing",
      };
      const before = structuredClone(input);
      const normalized = normalizeIdentification(input, {
        ...context,
        inferenceTier,
        hasVisualEvidence: mode.visual,
        hasAudioEvidence: mode.audio,
      });
      const candidates = [{ ...candidate, scientific_name: "Danaus gilippus" }];
      assertEquals(normalized, {
        identification: {
          ...draft,
          scientific_name: "Danaus plexippus",
          candidates,
          pet_identification: null,
          life_stage: undefined,
          reproductive_condition: undefined,
          sex: undefined,
          sex_confidence: undefined,
          sex_evidence: undefined,
          is_invasive: false,
          invasive_status_region: "Unavailable",
          invasive_rationale: unavailable,
          invasive_confidence: undefined,
          blur_score: 0,
        },
        audioSubjectKind: audioOnly ? "identified_non_human" : null,
        clientCandidates: candidates,
        clientLifeStage: "unknown",
        diagnostics: [],
      }, `${inferenceTier}/${mode.name}`);
      assertEquals(
        input,
        before,
        "caller-owned provider draft must be unchanged",
      );
    }
  }
});

Deno.test("candidate suppression uses the diagnostic boundary, preserves empty arrays, and leaves domain candidates intact", () => {
  for (const inferenceTier of ["flash", "pro"] as const) {
    for (
      const confidence_score of [0, 0.65, 0.75, 0.85, 0.95, 0.9899, 0.99, 1]
    ) {
      const result = normalizeIdentification({ ...draft, confidence_score }, {
        ...context,
        inferenceTier,
      });
      assertEquals(result.identification.candidates.length, 1);
      assertEquals(
        result.clientCandidates,
        confidence_score >= 0.99 ? null : result.identification.candidates,
      );
    }
    assertEquals(
      normalizeIdentification({ ...draft, candidates: [] }, {
        ...context,
        inferenceTier,
      }).clientCandidates,
      [],
    );
  }
});

Deno.test("pet identity is canonicalized before its label is sanitized", () => {
  const pet = {
    species_group: "dog",
    label: "  Golden   Retriever  ",
    label_type: "breed",
    confidence_score: 0.8,
    evidence: ["  synthetic   coat  "],
  };
  const input = {
    ...draft,
    common_name: "Dog",
    scientific_name: "Canis lupus",
    pet_identification: pet,
  };
  const result = normalizeIdentification(input, context).identification;
  assertEquals(result.scientific_name, "Canis lupus familiaris");
  assertEquals(result.pet_identification, {
    ...pet,
    label: "Golden Retriever",
    evidence: ["synthetic coat"],
  });
  assertEquals(
    normalizeIdentification({ ...draft, pet_identification: pet }, context)
      .identification.pet_identification,
    null,
  );
  assertEquals(
    normalizeIdentification({
      ...input,
      pet_identification: { ...pet, label: "Dog" },
    }, context)
      .identification.pet_identification,
    null,
  );
});

Deno.test("processed material clears biology, emits its existing diagnostic, and preserves specimen exceptions", () => {
  const input = {
    ...draft,
    common_name: "Wool Rug",
    scientific_name: "Ovis aries",
    ai_reasoning: "Synthetic woven artifact made from wool.",
    ecology_type: "domesticated",
    is_invasive: true,
    life_stage: "adult",
    sex: "female",
    sex_confidence: 0.8,
    individual_count: 2,
    ecological_interactions: ["synthetic interaction"],
  };
  const result = normalizeIdentification(input, context);
  assertEquals(result.identification, {
    ...input,
    is_biological_subject: false,
    is_live_capture: false,
    scientific_name: undefined,
    ecology_type: undefined,
    is_invasive: undefined,
    life_stage: undefined,
    reproductive_condition: undefined,
    sex: undefined,
    sex_confidence: undefined,
    sex_evidence: undefined,
    invasive_status_region: undefined,
    invasive_rationale: undefined,
    invasive_confidence: undefined,
    individual_count: undefined,
    ecological_interactions: undefined,
    pet_identification: null,
    candidates: [],
    blur_score: 0,
  });
  assertEquals(result.clientCandidates, []);
  assertEquals(result.clientLifeStage, undefined);
  assertEquals(result.diagnostics, [{
    event: "processed_material_demoted",
    reason: "processed_material_or_artifact_subject",
    previous_common_name: "Wool Rug",
    previous_scientific_name: "Ovis aries",
  }]);
  assertEquals(
    normalizeIdentification({
      ...input,
      ai_reasoning: "Synthetic preserved specimen with wool.",
    }, context).identification.is_biological_subject,
    true,
  );
});

Deno.test("audio discriminator selects all four states without reasoning-based human inference", () => {
  const audio = {
    ...context,
    hasVisualEvidence: false,
    hasAudioEvidence: true,
  };
  for (
    const [audio_subject_type, kind, common, scientific, biological] of [
      [
        "identified_non_human",
        "identified_non_human",
        "Danaus plexippus",
        "Danaus plexippus",
        true,
      ],
      [
        "unidentified_non_human",
        "unidentified_wildlife",
        "Unidentified Wildlife",
        undefined,
        true,
      ],
      ["human_only", "human", "Human", "Homo sapiens", true],
      [
        "no_confident_biological_source",
        "non_biological",
        "No Wildlife Detected",
        undefined,
        false,
      ],
    ] as const
  ) {
    const result = normalizeIdentification({
      ...draft,
      common_name: "Human",
      audio_subject_type,
      ai_reasoning: "Synthetic human speech mixed with non-human sound.",
      life_stage: "adult",
      sex: "male",
      sex_confidence: 0.8,
      sex_evidence: "Synthetic evidence.",
      is_invasive: true,
      invasive_confidence: 0.8,
    }, audio);
    assertEquals(result.audioSubjectKind, kind);
    assertEquals(result.identification.common_name, common);
    assertEquals(result.identification.scientific_name, scientific);
    assertEquals(result.identification.is_biological_subject, biological);
    assertEquals("audio_subject_type" in result.identification, false);
    if (kind !== "identified_non_human") {
      assertEquals(result.clientCandidates, []);
      assertEquals(result.clientLifeStage, undefined);
      assertEquals(
        result.identification.sex,
        kind === "human" ? "not_applicable" : undefined,
      );
      assertEquals(result.identification.sex_confidence, undefined);
      assertEquals(result.identification.sex_evidence, undefined);
      assertEquals(result.identification.invasive_confidence, undefined);
      assertEquals(result.identification.invasive_status_region, undefined);
    }
  }
  const unresolved = normalizeIdentification({
    ...draft,
    audio_subject_type: "identified_non_human",
    scientific_name: "Homo sapiens",
  }, audio);
  assertEquals(unresolved.audioSubjectKind, "unidentified_wildlife");
  assertEquals(unresolved.identification.scientific_name, undefined);
});

Deno.test("blended evidence preserves non-human identity over conflicting human common names", () => {
  const blended = { ...context, hasAudioEvidence: true };
  const animal = normalizeIdentification(
    { ...draft, common_name: "Human" },
    blended,
  );
  assertEquals(animal.audioSubjectKind, null);
  assertEquals(animal.identification.scientific_name, "Danaus plexippus");
  assertEquals(animal.clientCandidates?.length, 1);
  const human = normalizeIdentification({
    ...draft,
    scientific_name: "homo sapien",
  }, blended);
  assertEquals(human.audioSubjectKind, "human");
  assertEquals(human.identification.scientific_name, "Homo sapiens");
  assertEquals(human.clientCandidates, []);
  assertEquals(human.clientLifeStage, undefined);
});

Deno.test("location policy preserves existing fields and clears unsupported sex confidence", () => {
  const input = {
    ...draft,
    sex: "cannot_determine",
    sex_confidence: 0.7,
    sex_evidence: "  Synthetic evidence.  ",
    is_invasive: true,
    invasive_status_region: "  Synthetic Region  ",
    invasive_rationale: "  Synthetic rationale.  ",
    invasive_confidence: 0.8,
    life_stage: "adult",
  };
  for (const hasInvasiveLocationContext of [true, false]) {
    const result = normalizeIdentification(input, {
      ...context,
      hasInvasiveLocationContext,
    });
    assertEquals(result.identification.sex_confidence, undefined);
    assertEquals(result.identification.sex_evidence, undefined);
    assertEquals(result.identification.is_invasive, hasInvasiveLocationContext);
    assertEquals(
      result.identification.invasive_status_region,
      "Synthetic Region",
    );
    assertEquals(
      result.identification.invasive_rationale,
      "Synthetic rationale.",
    );
    assertEquals(
      result.identification.invasive_confidence,
      hasInvasiveLocationContext ? 0.8 : undefined,
    );
    assertEquals(result.clientLifeStage, "adult");
  }
  assertEquals(
    normalizeIdentification({
      ...draft,
      sex: "female",
      sex_confidence: 0.7,
      sex_evidence: "  Synthetic evidence.  ",
      image_quality: { ...draft.image_quality, sharpness: 8 },
    }, context).identification.sex_evidence,
    "Synthetic evidence.",
  );
  assertEquals(
    normalizeIdentification({
      ...draft,
      image_quality: { ...draft.image_quality, sharpness: 8 },
    }, context).identification.blur_score,
    0.2,
  );
});

Deno.test("non-biological natural identity survives while biology-only metadata is removed", () => {
  const result = normalizeIdentification({
    ...draft,
    is_biological_subject: false,
    scientific_name: "Quartz",
    common_name: "Quartz",
    ai_reasoning: "Synthetic crystalline mineral.",
    life_stage: "adult",
    individual_count: 1,
    is_invasive: true,
  }, context);
  assertEquals(result.identification.scientific_name, "Quartz");
  assertEquals(result.identification.life_stage, undefined);
  assertEquals(result.identification.individual_count, undefined);
  assertEquals(result.identification.is_invasive, undefined);
  assertEquals(result.clientCandidates, []);
});

Deno.test("invalid drafts fail parsing before legacy sanitizers can coerce out-of-contract fields", () => {
  for (
    const patch of [
      { candidates: Array(6).fill(candidate) },
      { candidates: [{ scientific_name: "Danaus gilippus" }] },
      { ai_reasoning: "x".repeat(2001) },
      { individual_count: 1.5 },
      { individual_count: 100000 },
      { confidence_score: NaN },
      { confidence_score: 1.1 },
      { life_stage: "fledgling" },
      { reproductive_condition: "brooding" },
      { sex: "worker" },
      { extracted_visual_traits: [] },
    ]
  ) {
    assertThrows(
      () => normalizeIdentification({ ...draft, ...patch }, context),
      ContractValueError,
    );
  }
  for (const value of [null, [], {}, "{}"]) {
    assertThrows(
      () => normalizeIdentification(value, context),
      ContractValueError,
    );
  }
  assertThrows(
    () =>
      normalizeIdentification(draft, {
        ...context,
        hasVisualEvidence: false,
        hasAudioEvidence: true,
      }),
    ContractValueError,
    "audio_model_response.audio_subject_type",
  );
});

Deno.test({
  name:
    "normalization needs no runtime permissions and clones nested provider fields",
  permissions: "none",
  fn() {
    const input = structuredClone(draft);
    Object.freeze(input);
    Object.freeze(input.candidates);
    Object.freeze(input.candidates[0]);
    Object.freeze(input.image_quality);
    const result = normalizeIdentification(input, context);
    result.identification.image_quality.sharpness = 1;
    result.identification.candidates[0].scientific_name =
      "Synthetic replacement";
    assertEquals(input, draft);
  },
});
