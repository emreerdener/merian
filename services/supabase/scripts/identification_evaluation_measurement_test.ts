import {
  assert,
  assertAlmostEquals,
  assertEquals,
  assertThrows,
} from "@std/assert";
import type { AIProviderOutcome } from "../functions/_shared/ai/contracts.ts";
import {
  openAIDraftFixture,
  openAITextFixture,
} from "../functions/_shared/ai/testing/openaiFixtures.ts";
import { syntheticCorpus } from "./identification_evaluation/fixtures.ts";
import { rateAwareCost } from "./identification_evaluation/measurementCost.ts";
import {
  improvementPercent,
  median,
} from "./identification_evaluation/exploratoryMeasurement.ts";
import {
  assignmentFor,
  estimateCost,
} from "./identification_evaluation/profiles.ts";
import {
  projectOutcome,
  projectUsage,
} from "./identification_evaluation/projection.ts";
import { percentiles } from "./identification_evaluation/reports.ts";
import {
  parseAttempt,
  parseEvaluationPricing,
  parseTaxonomy,
  type StoredUsage,
} from "./identification_evaluation/runContracts.ts";
import {
  assessMeasuredReference,
  assessReference,
} from "./identification_evaluation/scoring.ts";
import { resolveTaxon } from "./identification_evaluation/taxonomy.ts";
import type {
  Prediction,
  ReferenceLabel,
  Taxon,
} from "./identification_evaluation/contracts.ts";

const taxonomy = parseTaxonomy({
  version: "evaluation_taxonomy_v2",
  taxonomyVersion: "synthetic-taxonomy-v2",
  catalogRef: "synthetic-catalog",
  reviewRef: "synthetic-review",
  taxa: [
    {
      taxon: { id: "synthetic:1", rank: "species" },
      canonicalName: "Syntheticus primus",
      synonyms: ["Oldus primus", "Sharedus name"],
    },
    {
      taxon: { id: "synthetic:other", rank: "species" },
      canonicalName: "Syntheticus secundus",
      synonyms: ["Sharedus name"],
    },
    {
      taxon: { id: "synthetic:genus", rank: "genus" },
      canonicalName: "Syntheticus",
      synonyms: [],
    },
  ],
});
const named = (taxon: Taxon | null): Prediction => ({
  caseId: "c0002",
  outcome: "normalized",
  subject: "biological",
  resolution: "named",
  taxon,
  confidence: .95,
});
const label: ReferenceLabel = {
  subject: "biological",
  resolution: "named",
  supportedRank: "species",
  acceptableTaxa: [{ id: "synthetic:1", rank: "species" }],
};
const usage: StoredUsage = {
  promptTokens: 100,
  candidateTokens: 30,
  thinkingTokens: 10,
  totalTokens: 140,
  cachedTokens: 20,
  cacheWriteTokens: 30,
  toolTokens: 0,
  modalities: null,
};
function pricing(openai = true) {
  const common = {
    currency: "USD",
    service: "paid_standard_synchronous",
    retrievedAt: "2026-09-25T00:00:00.000Z",
    reviewRef: "synthetic-pricing",
    includesReasoning: true,
  };
  const model = {
    outputPerMillion: openai ? 10 : 4,
    maxInputTokens: 1050000,
    maxBillableOutputTokens: 8192,
    limitsEvidenceRef: "synthetic-limits",
  };
  return parseEvaluationPricing(
    openai
      ? {
        ...common,
        version: "evaluation_openai_pricing_v1",
        provider: "openai",
        sourceUrl: "https://developers.openai.com/api/docs/models/gpt-6-sol",
        models: [{
          ...model,
          model: "gpt-6-sol",
          inputPerMillion: { text: 2, image: 2, cached: .2, cacheWrite: 2.5 },
        }],
      }
      : {
        ...common,
        version: "evaluation_pricing_v1",
        sourceUrl: "https://ai.google.dev/gemini-api/docs/pricing",
        models: ["gemini-2.5-flash", "gemini-2.5-pro"].map((name) => ({
          ...model,
          model: name,
          inputPerMillion: { text: 1, image: 2, audio: 3, cached: .1 },
        })),
      },
  );
}

Deno.test("reviewed taxonomy resolves canonical names and synonyms without reference-only or first-match bias", () => {
  assertEquals(resolveTaxon(taxonomy, "  SYNTHETICUS   PRIMUS ").mapping, {
    status: "matched",
    match: "canonical",
  });
  assertEquals(
    resolveTaxon(taxonomy, "Oldus primus").taxon,
    label.acceptableTaxa[0],
  );
  assertEquals(resolveTaxon(taxonomy, "Oldus primus").mapping.match, "synonym");
  assertEquals(
    resolveTaxon(taxonomy, "Syntheticus secundus").taxon?.id,
    "synthetic:other",
  );
  assertEquals(resolveTaxon(taxonomy, "Sharedus name"), {
    taxon: null,
    mapping: { status: "ambiguous", match: null },
  });
  assertEquals(
    resolveTaxon(taxonomy, "Syntheticus primuz").mapping.status,
    "unmapped",
  );
  assertEquals(resolveTaxon(taxonomy, "Syntheticus").taxon?.rank, "genus");
  assert(taxonomy.version === "evaluation_taxonomy_v2");
  assertThrows(() =>
    parseTaxonomy({ ...taxonomy, taxa: [...taxonomy.taxa, taxonomy.taxa[0]] })
  );
  assertThrows(() =>
    parseTaxonomy({
      ...taxonomy,
      taxa: [{ ...taxonomy.taxa[0], synonyms: [" SYNTHETICUS PRIMUS "] }],
    })
  );
  assertThrows(() => parseTaxonomy({ ...taxonomy, reviewRef: "" }));
  const legacy = parseTaxonomy({
    version: "evaluation_taxonomy_v1",
    taxonomyVersion: "legacy",
    taxa: [{ taxon: label.acceptableTaxa[0], names: ["Syntheticus primus"] }],
  });
  assertEquals(resolveTaxon(legacy, " Syntheticus primus").taxon, null);
  assertThrows(() =>
    parseTaxonomy({
      ...legacy,
      taxa: [{ taxon: label.acceptableTaxa[0], names: ["A"] }, {
        taxon: { id: "synthetic:other", rank: "species" },
        names: ["a"],
      }],
    })
  );
});

Deno.test("measurement scoring separates missing mappings from disagreements and preserves subject evidence", () => {
  const matched = { status: "matched" as const, match: "canonical" as const };
  assertEquals(
    assessMeasuredReference(label, named(label.acceptableTaxa[0]), matched)
      .identity,
    "agreement",
  );
  assertEquals(
    assessMeasuredReference(
      label,
      named({ id: "synthetic:other", rank: "species" }),
      matched,
    ).identity,
    "disagreement",
  );
  const unknown = assessMeasuredReference(label, named(null), {
    status: "unmapped",
    match: null,
  });
  assertEquals(unknown.subject, "agreement");
  assertEquals(unknown.identity, "unmapped");
  assertEquals(
    assessMeasuredReference(label, named(null), {
      status: "ambiguous",
      match: null,
    }).identity,
    "ambiguous",
  );
  const genusLabel: ReferenceLabel = {
    ...label,
    supportedRank: "genus",
    acceptableTaxa: [{ id: "synthetic:genus", rank: "genus" }],
  };
  assertEquals(
    assessMeasuredReference(genusLabel, named(label.acceptableTaxa[0]), matched)
      .identity,
    "unsupported_specificity",
  );
  assertEquals(
    assessMeasuredReference(
      genusLabel,
      named({ id: "synthetic:genus", rank: "genus" }),
      matched,
    ).identity,
    "agreement",
  );
  const unresolved = {
    ...label,
    resolution: "unresolved" as const,
    supportedRank: null,
    acceptableTaxa: [],
  };
  assertEquals(
    assessMeasuredReference(unresolved, {
      ...named(null),
      outcome: "normalized",
      subject: "biological",
      resolution: "unresolved",
      taxon: null,
      confidence: 0,
    }, { status: "not_applicable", match: null }).identity,
    "valid_abstention",
  );
  assertEquals(
    assessMeasuredReference(
      { ...unresolved, subject: "non_biological" },
      named(null),
      { status: "unmapped", match: null },
    ).falseBiological,
    true,
  );
  for (
    const outcome of [
      "unattempted",
      "unknown_execution",
      "operational_failure",
    ] as const
  ) {
    assertEquals(
      assessMeasuredReference(label, { caseId: "c0002", outcome }, null)
        .identity,
      "no_result",
    );
  }
  assertEquals(
    assessMeasuredReference(null, named(null), null).identity,
    "unverified",
  );
  assertEquals(assessReference(label, named(null)).correct, false); // Historical scoring has not been reinterpreted.
});

Deno.test("v2 projection stores bounded mapping/usage while v1 artifacts keep their shape", async () => {
  const input = syntheticCorpus().cases[1].input;
  const a = await assignmentFor(
    input,
    openAITextFixture(),
    "openai_gpt_6_sol",
    1,
    null,
  );
  const facts = {
    providerDurationMs: 7,
    providerCompletedAt: 0,
    returnedModel: a.model,
    usage: { ...usage, modalityBreakdown: {} },
    finishReason: null,
    responseCharacters: 1,
  };
  for (
    const [name, status] of [["Oldus primus", "matched"], [
      "Sharedus name",
      "ambiguous",
    ], ["PRIVATE_UNMAPPED", "unmapped"]]
  ) {
    const outcome: AIProviderOutcome = {
      ...facts,
      kind: "draft",
      draft: {
        ...openAIDraftFixture(),
        scientific_name: name,
        ai_reasoning: "PRIVATE_EXPLANATION",
        candidates: [],
      },
    };
    const r = projectOutcome(outcome, input, a, "0".repeat(64), taxonomy, null);
    assertEquals(r.version, "evaluation_openai_attempt_v2");
    assertEquals(r.mapping?.status, status);
    assertEquals(r.usage?.cacheWriteTokens, 30);
    assert(!JSON.stringify(r).includes("PRIVATE_"));
    assert(!JSON.stringify(r).includes(name));
    assertThrows(() => parseAttempt({ ...r, raw: "PRIVATE" }));
    assertThrows(() =>
      parseAttempt({ ...r, version: "evaluation_openai_attempt_v1" })
    );
    assertThrows(() =>
      parseAttempt({ ...r, mapping: { status: "not_applicable", match: null } })
    );
    const legacy = parseTaxonomy({
      version: "evaluation_taxonomy_v1",
      taxonomyVersion: "legacy",
      taxa: [{ taxon: label.acceptableTaxa[0], names: ["Oldus primus"] }],
    });
    const old = projectOutcome(outcome, input, a, "0".repeat(64), legacy, null);
    assertEquals(old.version, "evaluation_openai_attempt_v1");
    assert(!("mapping" in old));
    assert(!("cacheWriteTokens" in old.usage!));
    assertEquals(parseAttempt(old), old);
  }
  const failure = projectOutcome(
    { ...facts, kind: "operational_failure" },
    input,
    a,
    "0".repeat(64),
    taxonomy,
    null,
  );
  assertEquals(failure.mapping, null);
  assertEquals(failure.candidateMappings, null);
  assertThrows(() =>
    parseAttempt({ ...failure, mapping: { status: "unmapped", match: null } })
  );
  assertEquals(
    projectUsage({ ...facts.usage, cacheWriteTokens: Infinity }, true)
      ?.cacheWriteTokens,
    null,
  );
});

Deno.test("rate-aware cost separates cache categories and bills reasoning once without weakening the guard", () => {
  const p = pricing();
  const r = rateAwareCost(p, "gpt-6-sol", usage);
  assertEquals(r.status, "complete");
  assertAlmostEquals(r.usd!, (50 * 2 + 20 * .2 + 30 * 2.5 + 40 * 10) / 1e6);
  const conservative = estimateCost(p, "gpt-6-sol", usage);
  assertEquals(conservative, (100 * 2.5 + 40 * 10) / 1e6);
  for (const writes of [undefined, null]) {
    assertEquals(
      rateAwareCost(p, "gpt-6-sol", { ...usage, cacheWriteTokens: writes })
        .reason,
      "cache_write_missing",
    );
    assertEquals(
      estimateCost(p, "gpt-6-sol", { ...usage, cacheWriteTokens: writes }),
      conservative,
    );
  }
  for (
    const change of [
      { cacheWriteTokens: 81 },
      { totalTokens: 141 },
      { toolTokens: null },
      { thinkingTokens: null },
      { cachedTokens: 101 },
    ]
  ) {
    assertEquals(
      rateAwareCost(p, "gpt-6-sol", { ...usage, ...change }).usd,
      null,
    );
  }
  const geminiUsage: StoredUsage = {
    ...usage,
    cacheWriteTokens: null,
    modalities: {
      prompt: { text: 20, image: 80, audio: 0 },
      cached: { text: 0, image: 20, audio: 0 },
      candidates: { text: 30, image: 0, audio: 0 },
      tool: { text: 0, image: 0, audio: 0 },
    },
  };
  assertAlmostEquals(
    rateAwareCost(pricing(false), "gemini-2.5-pro", geminiUsage).usd!,
    (20 + 60 * 2 + 20 * .1 + 40 * 4) / 1e6,
  );
  assertEquals(
    rateAwareCost(pricing(false), "gemini-2.5-pro", {
      ...geminiUsage,
      modalities: null,
    }).reason,
    "modality_usage_missing",
  );
  assertEquals(
    rateAwareCost(pricing(false), "gemini-2.5-pro", {
      ...geminiUsage,
      cachedTokens: 21,
    }).usd,
    null,
  );
  assertEquals(rateAwareCost(null, "gpt-6-sol", usage).status, "not_measured");
});

Deno.test("new median and percentage definitions leave legacy nearest-rank p50 unchanged", () => {
  assertEquals(median([4, 1, 2, 3]), 2.5);
  assertEquals(median([3, 1, 2]), 2);
  assertEquals(median([]), null);
  assertEquals(percentiles([4, 1, 2, 3]).p50, 2);
  assertEquals(improvementPercent(100, 90), 10);
  assertEquals(improvementPercent(100, 110), -10);
  assertEquals(improvementPercent(0, 0), null);
  assertEquals(improvementPercent(null, 5), null);
  assertThrows(() => median([NaN]));
});
