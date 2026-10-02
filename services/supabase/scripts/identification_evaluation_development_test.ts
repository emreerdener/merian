import { assert, assertEquals } from "@std/assert";
import { openAIDraftFixture } from "../functions/_shared/ai/testing/openaiFixtures.ts";
import { solPrimaryDraftFixture } from "../functions/_shared/ai/testing/openaiSolPrimaryFixtures.ts";
import { projectDevelopmentDraft } from "./identification_evaluation/developmentProjection.ts";
import { type ReviewedTaxonomy } from "./identification_evaluation/taxonomy.ts";

// Invented names and IDs are contract fixtures, never biological references.
const taxonomy: ReviewedTaxonomy = {
  version: "evaluation_taxonomy_v2",
  taxonomyVersion: "synthetic-v1",
  catalogRef: "synthetic-catalog",
  reviewRef: "synthetic-review",
  taxa: [
    {
      taxon: { id: "test:species", rank: "species" },
      canonicalName: "Syntheticus example",
      synonyms: ["Syntheticus alias", "Shared alias"],
    },
    {
      taxon: { id: "test:genus", rank: "genus" },
      canonicalName: "Syntheticus",
      synonyms: ["Shared alias"],
    },
    {
      taxon: { id: "test:family", rank: "family" },
      canonicalName: "Syntheticaceae",
      synonyms: [],
    },
    {
      taxon: { id: "test:dog", rank: "species" },
      canonicalName: "Canis lupus familiaris",
      synonyms: [],
    },
  ],
};
const project = (
  draft: unknown,
  profile: "legacy" | "explicit_primary" = "legacy",
) => projectDevelopmentDraft("c0001", profile, draft, taxonomy);

Deno.test("development flags preserve pre-normalization evidence without retaining content", () => {
  for (
    const [name, annotation, changed] of [
      ["Syntheticus example", false, false],
      ["  Syntheticus   example  ", false, true],
      ["Syntheticus example L.", true, true],
      ["cf. Syntheticus example", true, true],
    ] as const
  ) {
    const draft = {
      ...openAIDraftFixture(),
      scientific_name: name,
      ai_reasoning: "PRIVATE SYNTHETIC SENTINEL",
      life_stage: null,
    };
    const original = structuredClone(draft);
    const result = project(draft), d = result.diagnostics;
    assertEquals(d.before.annotation, annotation);
    assertEquals(d.after, { present: true, annotation: false });
    assertEquals(d.sanitizerChanged, changed);
    assertEquals(d.petAliasChanged, false);
    assertEquals(d.nameChanged, changed);
    assertEquals(d.afterMapping, { status: "matched", match: "canonical" });
    assertEquals(d.catalogRank, "species");
    assertEquals(d.declaredResolution, null);
    assertEquals(d.rankAgreement, "not_declared");
    assertEquals(d.status, "accepted");
    assert(!JSON.stringify(result).includes("Syntheticus"));
    assert(!JSON.stringify(result).includes("SENTINEL"));
    assertEquals(draft, original);
    assertEquals(project(draft), result);
  }
});

Deno.test("development distinguishes pet canonicalization, synonyms, ambiguity and unmapped names", () => {
  const dog = project({
    ...openAIDraftFixture(),
    scientific_name: "Canis familiaris",
    common_name: "Dog",
  }).diagnostics;
  assertEquals(dog.petAliasChanged, true);
  assertEquals(dog.beforeMapping?.status, "unmapped");
  assertEquals(dog.afterMapping?.status, "matched");
  for (
    const [name, status, match] of [
      ["Syntheticus alias", "matched", "synonym"],
      ["Shared alias", "ambiguous", null],
      ["Unknownus example", "unmapped", null],
    ] as const
  ) {
    const r = project(
      { ...solPrimaryDraftFixture(), scientific_name: name },
      "explicit_primary",
    );
    assertEquals(r.diagnostics.afterMapping, { status, match });
    assertEquals(
      r.diagnostics.rankAgreement,
      status === "matched" ? "consistent" : "unverified",
    );
    if (status !== "matched") {
      assertEquals(r.diagnostics.catalogRank, null);
      assert(r.observation.prediction.outcome === "normalized");
      assertEquals(r.observation.prediction.taxon, null);
    }
  }
});

Deno.test("all five primary states preserve explicit meaning and zero-confidence abstention", () => {
  for (
    const resolution of [
      "species",
      "genus",
      "family",
      "unresolved_biological",
      "non_biological",
    ] as const
  ) {
    const r = project({
      ...solPrimaryDraftFixture(resolution),
      confidence_score: 0,
    }, "explicit_primary");
    assertEquals(r.diagnostics.declaredResolution, resolution);
    assertEquals(r.diagnostics.effectiveResolution, resolution);
    assertEquals(r.diagnostics.status, "accepted");
    assert(r.observation.prediction.outcome === "normalized");
    assertEquals(r.observation.prediction.confidence, 0);
    if (["species", "genus", "family"].includes(resolution)) {
      assertEquals(r.observation.prediction.taxon?.rank, resolution);
    } else {
      assertEquals(r.observation.prediction.taxon, null);
      assertEquals(r.diagnostics.afterMapping?.status, "not_applicable");
    }
  }
});

Deno.test("catalog rank conflicts never become scored identities via coercion", () => {
  const r = project({
    ...solPrimaryDraftFixture("genus"),
    scientific_name: "Syntheticus example",
  }, "explicit_primary");
  assertEquals(r.diagnostics.status, "rank_conflict");
  assertEquals(r.diagnostics.declaredResolution, "genus");
  assertEquals(r.diagnostics.catalogRank, "species");
  assertEquals(r.observation, {
    prediction: { caseId: "c0001", outcome: "invalid_output" },
    mapping: null,
  });
});

Deno.test("qualifiers and malformed primary drafts reject before lossy sanitation", () => {
  for (
    const change of [
      { scientific_name: "cf. Syntheticus example" },
      { scientific_name: "Syntheticus sp." },
      { scientific_name: "Syntheticus example var. minor" },
      { resolution: undefined },
      { is_biological_subject: false },
      { scientific_name: "x".repeat(256) },
      { unexpected: "PRIVATE SENTINEL" },
    ]
  ) {
    const r = project(
      { ...solPrimaryDraftFixture(), ...change },
      "explicit_primary",
    );
    assertEquals(r.observation.prediction.outcome, "invalid_output");
    assertEquals(r.diagnostics.stage, "decode");
    assertEquals(r.diagnostics.after, null);
    assert(!JSON.stringify(r).includes("SENTINEL"));
  }
  assertEquals(
    project({
      ...solPrimaryDraftFixture(),
      scientific_name: "cf. Syntheticus example",
    }, "explicit_primary").diagnostics.before.annotation,
    true,
  );
});

Deno.test("processed material demotion keeps declared and effective resolutions separate", () => {
  const r = project({
    ...solPrimaryDraftFixture(),
    scientific_name: "Ovis aries",
    common_name: "Wool Rug",
    extracted_visual_traits: [
      "woven wool",
      "flat textile",
      "manufactured edges",
    ],
    ai_reasoning: "A manufactured textile made from processed wool.",
  }, "explicit_primary");
  assertEquals(r.diagnostics.declaredResolution, "species");
  assertEquals(r.diagnostics.effectiveResolution, "non_biological");
  assertEquals(r.diagnostics.processedMaterialDemoted, true);
  assertEquals(r.diagnostics.rankAgreement, "not_applicable");
  assertEquals(r.diagnostics.afterMapping?.status, "not_applicable");
  assert(!JSON.stringify(r).includes("Ovis"));
  assert(!JSON.stringify(r).includes("Wool"));
});
