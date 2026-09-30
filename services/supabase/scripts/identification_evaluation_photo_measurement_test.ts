import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { AIProviderOutcome } from "../functions/_shared/ai/contracts.ts";
import {
  openAIDraftFixture,
  openAIPhotoRequestFixture,
} from "../functions/_shared/ai/testing/openaiFixtures.ts";
import { auditPhotoTaxonomyFiles } from "./audit_photo_taxonomy.ts";
import type { ReferenceLabel } from "./identification_evaluation/contracts.ts";
import type { FactCard } from "./identification_evaluation/explanationContracts.ts";
import { syntheticCorpus } from "./identification_evaluation/fixtures.ts";
import type { PhotoModelAssignment } from "./identification_evaluation/photoModelPreparation.ts";
import { parsePhotoModelPricing } from "./identification_evaluation/photoModelContracts.ts";
import {
  parsePhotoModelMeasurementRecord,
  parsePhotoModelRecord,
  projectMeasuredPhotoModelOutcome,
  projectPhotoModelOutcome,
} from "./identification_evaluation/photoModelRecords.ts";
import { auditPhotoTaxonomy } from "./identification_evaluation/photoTaxonomyAudit.ts";
import { assessMeasuredReference } from "./identification_evaluation/scoring.ts";
import {
  parseTaxonomy,
  resolveTaxon,
  type ReviewedTaxonomy,
} from "./identification_evaluation/taxonomy.ts";

// Invented taxa and prices test mechanics only; no media, provider, or credential.
const identity = { id: "synthetic:species", rank: "species" as const };
const taxonomy: ReviewedTaxonomy = {
  version: "evaluation_taxonomy_v2",
  taxonomyVersion: "synthetic-catalog-v2",
  catalogRef: "synthetic-catalog",
  reviewRef: "synthetic-review",
  taxa: [
    {
      taxon: identity,
      canonicalName: "Syntheticus example",
      synonyms: ["Oldus example", "Shared name"],
    },
    {
      taxon: { id: "synthetic:other", rank: "species" },
      canonicalName: "Otherus example",
      synonyms: ["Shared name"],
    },
    {
      taxon: { id: "synthetic:genus", rank: "genus" },
      canonicalName: "Syntheticus",
      synonyms: [],
    },
    {
      taxon: { id: "synthetic:family", rank: "family" },
      canonicalName: "Syntheticaceae",
      synonyms: [],
    },
  ],
};
const input = { ...syntheticCorpus().cases[0].input, observationTexts: [] };
const reference: ReferenceLabel = {
  subject: "biological",
  resolution: "named",
  supportedRank: "species",
  acceptableTaxa: [identity],
};
const corpus = () => ({
  version: "identification_exploratory_corpus_v1",
  id: "synthetic-audit-v1",
  kind: "exploratory",
  evidenceOrigin: "synthetic",
  taxonomyVersion: taxonomy.taxonomyVersion,
  preparationVersion: "synthetic-v1",
  splitSeed: 42,
  eligibility: null,
  cases: [{
    input,
    provisionalReference: reference,
    curation: { kind: "synthetic" },
  }],
});
const assignment: PhotoModelAssignment = {
  profile: "openai_photo_luna_low_v1",
  model: "gpt-6-luna",
  ordinal: 1,
  phase: "screen",
  attempt: 1,
  caseId: input.caseId,
  inputDigest: "1".repeat(64),
  referenceDigest: "2".repeat(64),
  factsDigest: "3".repeat(64),
  snapshotDigest: "4".repeat(64),
  requestDigest: "5".repeat(64),
  reservedNanoUsd: 1000000,
};
const runDigest = "6".repeat(64), assignmentDigest = "7".repeat(64);
const card: FactCard = {
  caseId: input.caseId,
  inputDigest: assignment.inputDigest,
  observed: ["Invented organism."],
  missing: [],
  acceptableReasons: ["Test only."],
  rankLimit: "Synthetic reference only.",
  requirements: ["decision_evidence", "rank_limit"],
};
const pricing = parsePhotoModelPricing({
  version: "photo_model_pricing_v1",
  retrievedAt: "2026-09-28T00:00:00.000Z",
  reviewRef: "synthetic-price",
  currency: "USD",
  billing: "paid_standard_synchronous",
  profiles: {
    openai_photo_luna_low_v1: {
      model: "gpt-6-luna",
      source: "https://developers.openai.com/api/docs/models/gpt-6-luna",
      inputCeilingUsdPerMillion: .25,
      outputCeilingUsdPerMillion: .75,
    },
    openai_photo_sol_low_v1: {
      model: "gpt-6-sol",
      source: "https://developers.openai.com/api/docs/models/gpt-6-sol",
      inputCeilingUsdPerMillion: 5,
      outputCeilingUsdPerMillion: 15,
    },
  },
});
function outcome(name: string | null): AIProviderOutcome {
  return {
    kind: "draft",
    returnedModel: assignment.model,
    serviceTier: "default",
    providerDurationMs: 123,
    providerCompletedAt: 1,
    finishReason: "completed",
    responseCharacters: 100,
    mediaSafety: {
      provider: "openai",
      policy: "openai_photo_moderation_v1",
      disposition: "allowed",
    },
    usage: {
      promptTokens: 100,
      outputTokens: 40,
      candidateTokens: 30,
      thinkingTokens: 10,
      cachedTokens: 0,
      cacheWriteTokens: 0,
      totalTokens: 140,
      toolTokens: 0,
      modalityBreakdown: {},
    },
    draft: {
      ...openAIDraftFixture(),
      scientific_name: name,
      common_name: "Private name sentinel",
      ai_reasoning: "Private explanation sentinel",
      is_biological_subject: true,
    },
  };
}
function args(value = outcome("Syntheticus example")) {
  return [
    value,
    input,
    openAIPhotoRequestFixture(),
    card,
    assignment,
    runDigest,
    assignmentDigest,
    parseTaxonomy(taxonomy),
    pricing,
  ] as const;
}
const parse = (value: unknown) =>
  parsePhotoModelMeasurementRecord(
    value,
    assignment,
    runDigest,
    assignmentDigest,
  );

Deno.test("photo measurement keeps canonical, synonym, ambiguous, unmapped and higher-rank identities without saving names", () => {
  for (
    const [name, status, match, rank] of [
      ["Syntheticus example", "matched", "canonical", "species"],
      ["Oldus example", "matched", "synonym", "species"],
      ["Shared name", "ambiguous", null, null],
      ["Unknownus example", "unmapped", null, null],
      ["Syntheticus", "matched", "canonical", "genus"],
      ["Syntheticaceae", "matched", "canonical", "family"],
    ] as const
  ) {
    const { record } = projectMeasuredPhotoModelOutcome(...args(outcome(name)));
    assertEquals(record.reason, "completed");
    assertEquals(record.mapping, { status, match });
    assert(record.prediction.outcome === "normalized");
    assertEquals(record.prediction.resolution, "named");
    assertEquals(record.prediction.taxon?.rank ?? null, rank);
    const stored = JSON.stringify(record);
    for (
      const forbidden of [
        name,
        "Private",
        "scientific_name",
        "ai_reasoning",
        "data:image",
      ]
    ) {
      assert(!stored.includes(forbidden));
    }
  }
});

Deno.test("photo measurement versions cannot be mixed and mapping semantics cannot contradict the prediction", () => {
  const legacy = projectPhotoModelOutcome(...args()).record;
  const measured = projectMeasuredPhotoModelOutcome(...args()).record;
  const { mapping: _mapping, version: _version, ...rest } = measured;
  assertEquals({ ...legacy, normalizationMs: 0 }, {
    ...rest,
    version: "photo_model_attempt_v1",
    normalizationMs: 0,
  });
  const legacyArgs: Parameters<typeof projectMeasuredPhotoModelOutcome> = [
    ...args(),
  ];
  legacyArgs[7] = parseTaxonomy({
    version: "evaluation_taxonomy_v1",
    taxonomyVersion: "synthetic-legacy",
    taxa: [{
      taxon: identity,
      names: ["Syntheticus example", "Oldus example"],
    }],
  });
  legacyArgs[0] = outcome("Oldus example");
  assertEquals(
    projectPhotoModelOutcome(...legacyArgs).record.reason,
    "completed",
  );
  assertThrows(() => projectMeasuredPhotoModelOutcome(...legacyArgs));
  assertThrows(() => parse(legacy));
  assertThrows(() =>
    parsePhotoModelRecord(measured, assignment, runDigest, assignmentDigest)
  );
  for (
    const changed of [
      { ...measured, extra: "prose" },
      { ...measured, runDigest: "8".repeat(64) },
      { ...measured, assignmentDigest: "8".repeat(64) },
      { ...measured, mapping: { status: "ambiguous", match: null } },
      { ...measured, mapping: { status: "matched", match: null } },
      {
        ...measured,
        mapping: { status: "matched", match: "canonical", name: "prose" },
      },
    ]
  ) assertThrows(() => parse(changed));
  const unmapped =
    projectMeasuredPhotoModelOutcome(...args(outcome("Unknownus example")))
      .record;
  assertThrows(() =>
    parse({ ...unmapped, mapping: { status: "not_applicable", match: null } })
  );
  assertThrows(() =>
    parse({ ...unmapped, mapping: { status: "matched", match: "canonical" } })
  );
});

Deno.test("photo measurement gives abstentions, non-biological results and normalization failures no applicable identity", () => {
  const absent = outcome(null);
  assert(absent.kind === "draft");
  for (
    const value of [absent, {
      ...absent,
      draft: { ...(absent.draft as object), is_biological_subject: false },
    }]
  ) {
    const { record } = projectMeasuredPhotoModelOutcome(...args(value));
    assertEquals(record.reason, "completed");
    assertEquals(record.mapping, { status: "not_applicable", match: null });
    assertThrows(() =>
      parse({ ...record, mapping: { status: "unmapped", match: null } })
    );
  }
  const record = projectMeasuredPhotoModelOutcome(
    outcome("Syntheticus example"),
    { ...input, inputGroup: "description" },
    openAIPhotoRequestFixture(),
    card,
    assignment,
    runDigest,
    assignmentDigest,
    taxonomy,
    pricing,
  ).record;
  assertEquals(record.reason, "normalization_failed");
  assertEquals(record.mapping, { status: "not_applicable", match: null });
});

Deno.test("photo measurement scoring preserves mapping gaps separately from errors or abstention", () => {
  for (
    const [name, expected] of [["Shared name", "ambiguous"], [
      "Unknownus example",
      "unmapped",
    ], ["Otherus example", "disagreement"]] as const
  ) {
    const { record } = projectMeasuredPhotoModelOutcome(...args(outcome(name)));
    assertEquals(
      assessMeasuredReference(reference, record.prediction, record.mapping)
        .identity,
      expected,
    );
  }
  const genusReference: ReferenceLabel = {
    ...reference,
    supportedRank: "genus",
    acceptableTaxa: [taxonomy.taxa[2].taxon],
  };
  for (
    const [name, expected] of [["Syntheticus", "agreement"], [
      "Syntheticus example",
      "unsupported_specificity",
    ]] as const
  ) {
    const { record } = projectMeasuredPhotoModelOutcome(...args(outcome(name)));
    assertEquals(
      assessMeasuredReference(genusReference, record.prediction, record.mapping)
        .identity,
      expected,
    );
  }
});

Deno.test("catalog audit finds duplicate canonical identities and synonym ambiguity without rewriting sources", async () => {
  const t = structuredClone(taxonomy);
  t.taxa.push({
    taxon: { id: "synthetic:duplicate", rank: "species" },
    canonicalName: "SYNTHETICUS   EXAMPLE",
    synonyms: [],
  });
  t.taxa[1].synonyms.push("Syntheticus");
  const before = JSON.stringify(t);
  const report = await auditPhotoTaxonomy(corpus(), t);
  assertEquals(report.catalogConsistency, "blocked");
  assertEquals(report.counts.nameCollisions, 3);
  assertEquals(report.counts.duplicateCanonicalNames, 1);
  assertEquals(report.counts.brokenReferences, 0);
  assertEquals(
    new Set(report.collisions.map((c) => c.kind)),
    new Set(["duplicate_canonical", "canonical_synonym", "synonym_overlap"]),
  );
  assertEquals(JSON.stringify(t), before);
  assert(!JSON.stringify(report).includes("Syntheticus"));
  assertEquals(
    resolveTaxon(parseTaxonomy(t), "Syntheticus example").mapping.status,
    "ambiguous",
  );
});

Deno.test("catalog audit blocks absent or mismatched references and does not turn a clean catalog into approval", async () => {
  const t = {
    ...taxonomy,
    taxa: taxonomy.taxa.map((item) => ({ ...item, synonyms: [] })),
  };
  const report = await auditPhotoTaxonomy(corpus(), t);
  assertEquals(report.catalogConsistency, "clear");
  assertEquals(report.dispatchAuthorized, false);
  assertEquals(report.referenceReviewComplete, false);
  const missing = await auditPhotoTaxonomy(corpus(), {
    ...t,
    taxa: t.taxa.slice(1),
  });
  assertEquals(missing.referenceIssues, [{
    caseId: input.caseId,
    taxon: identity,
    issue: "missing_id",
  }]);
  const mismatch = await auditPhotoTaxonomy(corpus(), {
    ...t,
    taxa: t.taxa.map((item) => ({
      ...item,
      taxon: { ...item.taxon, rank: "genus" },
    })),
  });
  assertEquals(mismatch.referenceIssues[0].issue, "rank_mismatch");
  const c = corpus();
  const noReference = await auditPhotoTaxonomy({
    ...c,
    cases: [{ ...c.cases[0], provisionalReference: null }],
  }, t);
  assertEquals(noReference.unreferencedCaseIds, [input.caseId]);
  assertEquals(noReference.catalogConsistency, "blocked");
  await assertRejects(() =>
    auditPhotoTaxonomy({ ...c, taxonomyVersion: "different" }, t)
  );
  await assertRejects(() => auditPhotoTaxonomy(c, { ...t, extra: true }));
});

Deno.test("catalog audit applies resolver normalization, includes cross-rank collisions, and bounds details", async () => {
  const t = {
    ...taxonomy,
    taxa: Array.from({ length: 101 }, (_, i) => [
      {
        taxon: { id: `a:${i}`, rank: "genus" },
        canonicalName: `Sýnthetic ${i}`,
        synonyms: [],
      },
      {
        taxon: { id: `b:${i}`, rank: "species" },
        canonicalName: `SÝNTHETIC   ${i}`,
        synonyms: [],
      },
    ]).flat(),
  };
  const report = await auditPhotoTaxonomy(corpus(), t);
  assertEquals(report.counts.nameCollisions, 101);
  assertEquals(report.collisions.length, 100);
  assertEquals(report.collisionDetailsTruncated, true);
  assertEquals(report.collisions[0].taxa.map((o) => o.taxon.rank), [
    "genus",
    "species",
  ]);
  const many = {
    ...taxonomy,
    taxa: Array.from(
      { length: 40 },
      (_, i) => ({
        taxon: { id: `same:${i}`, rank: "species" },
        canonicalName: "Same name",
        synonyms: [],
      }),
    ),
  };
  const bounded = await auditPhotoTaxonomy(corpus(), many);
  assertEquals(bounded.collisions[0].taxonCount, 40);
  assertEquals(bounded.collisions[0].taxa.length, 32);
  assertEquals(bounded.collisions[0].taxaTruncated, true);
});

Deno.test("read-only catalog command rejects an unavailable packet without credential access", async () => {
  await assertRejects(() =>
    auditPhotoTaxonomyFiles(
      "services/supabase/scripts/nonexistent-synthetic-packet",
    )
  );
});
