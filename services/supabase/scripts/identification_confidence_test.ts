import {
  assert,
  assertAlmostEquals,
  assertEquals,
  assertThrows,
} from "@std/assert";
import { parseConfidenceCorpus } from "./identification_evaluation/confidenceCorpus.ts";
import {
  CONFIDENCE_PROTOCOL as P,
  confidenceRate,
} from "./identification_evaluation/confidenceProtocol.ts";
import {
  confidenceAssessment,
  confidenceRows,
  confidenceSplitReport,
  selectConfidenceCutoff,
} from "./identification_evaluation/confidenceScoring.ts";
import { projectConfidenceOutcome } from "./identification_evaluation/confidenceProjection.ts";
import {
  confidenceFixture,
  confidenceOutcome,
} from "./identification_evaluation/testing/confidenceFixtures.ts";
import {
  parseTaxonomy,
  resolveTaxon,
} from "./identification_evaluation/taxonomy.ts";
import { confidencePolicy } from "./identification_evaluation/profiles.ts";
import { assignConfidenceSplits } from "./identification_evaluation/confidenceSampling.ts";

Deno.test("development selection enforces 40 Strong and exactly 95 percent observed correctness without collapsing Possible", () => {
  const { corpus, observations } = confidenceFixture();
  for (const [i, v] of observations.entries()) {
    assert(v.prediction.outcome === "normalized");
    v.prediction = {
      ...v.prediction,
      confidence: i < 40 ? .70 : .60,
      taxon: i < 2
        ? { id: "synthetic:other", rank: "species" }
        : v.prediction.taxon,
    };
  }
  const select = () =>
    selectConfidenceCutoff(
      confidenceRows(corpus.cases, observations).slice(0, 100),
    );
  assertEquals(select(), .61); // 38/40 qualifies; exactly .60 stays Possible.
  const extraError = observations[2];
  assert(extraError.prediction.outcome === "normalized");
  extraError.prediction = {
    ...extraError.prediction,
    taxon: { id: "synthetic:other", rank: "species" },
  };
  assertEquals(select(), null); // Complete development, 37/40 is insufficient.
  extraError.prediction = {
    ...extraError.prediction,
    taxon: { id: "synthetic:species", rank: "species" },
    confidence: .60,
  };
  assertEquals(select(), null); // 39 Strong cannot select a threshold.
  assertEquals(
    confidenceAssessment(corpus, observations, null).decision,
    "no_development_cutoff",
  );
});

Deno.test("seeded sampling reproduces category quotas, groups and development-only references independently of input order", () => {
  const { corpus, taxonomy } = confidenceFixture();
  const expected = Object.fromEntries(
    corpus.cases.map((c) => [c.input.caseId, c.input.split]),
  );
  const reversed = assignConfidenceSplits([...corpus.cases].reverse());
  assertEquals(
    Object.fromEntries(reversed.map((c) => [c.input.caseId, c.input.split])),
    expected,
  );
  corpus.kind = "reference";
  for (const c of corpus.cases) {
    c.curation = {
      kind: "reviewed",
      permission: "openai_evaluation",
      sourceRecordRef: "synthetic-source",
      referenceRecordRef: "synthetic-reference",
      reviewerRefs: ["synthetic-a", "synthetic-b"],
      rightsApproved: true,
      personalDataExcluded: true,
      nearDuplicatesReviewed: true,
      referenceVerified: true,
      adjudication: "agreed",
      developmentOnly: c.input.caseId === corpus.cases[100].input.caseId,
    };
  }
  const forced = corpus.cases[100].input.caseId;
  corpus.cases[101].input = {
    ...corpus.cases[101].input,
    groupId: corpus.cases[100].input.groupId,
  };
  corpus.cases = assignConfidenceSplits(corpus.cases);
  assertEquals(
    corpus.cases.find((c) => c.input.caseId === forced)?.input.split,
    "development",
  );
  assertEquals(corpus.cases[100].input.split, corpus.cases[101].input.split);
  assertEquals(parseConfidenceCorpus(corpus, taxonomy).corpus, corpus);
});

Deno.test("confidence corpus freezes proportions, references, rights, split and taxonomy before collection", () => {
  const f = confidenceFixture();
  assertEquals(parseConfidenceCorpus(f.corpus, f.taxonomy).corpus, f.corpus);
  const mutations = [
    (c: typeof f.corpus) => {
      c.cases.pop();
    },
    (c: typeof f.corpus) => {
      c.cases[0].category = "lookalike";
    },
    (c: typeof f.corpus) => {
      c.cases[0].reference = {
        ...c.cases[0].reference,
        subject: "indeterminate",
      };
    },
    (c: typeof f.corpus) => {
      c.cases[0].input = {
        ...c.cases[0].input,
        observationTexts: ["label leak"],
      };
    },
    (c: typeof f.corpus) => {
      c.cases[100].input = {
        ...c.cases[100].input,
        groupId: c.cases[0].input.groupId,
      };
    },
    (c: typeof f.corpus) => {
      c.cases[100].input = {
        ...c.cases[100].input,
        assets: c.cases[0].input.assets,
      };
    },
    (c: typeof f.corpus) => {
      c.kind = "reference";
    },
  ];
  for (const mutate of mutations) {
    const c = structuredClone(f.corpus);
    mutate(c);
    assertThrows(() => parseConfidenceCorpus(c, f.taxonomy));
  }
  const unknown = structuredClone(f.corpus);
  unknown.cases[0].reference = {
    ...unknown.cases[0].reference,
    acceptableTaxa: [{ id: "unknown", rank: "species" }],
  };
  assertThrows(() => parseConfidenceCorpus(unknown, f.taxonomy));
});

Deno.test("names resolve rank through the frozen catalog only, with exact synonyms and ambiguous mapping failures", () => {
  const f = confidenceFixture(), c = f.corpus.cases[0];
  const outcome = confidenceOutcome(c);
  assert(outcome.kind === "draft");
  const run = (name: string) =>
    projectConfidenceOutcome(
      c.input.caseId,
      {
        ...outcome,
        draft: { ...(outcome.draft as object), scientific_name: name },
      },
      f.taxonomy,
      f.pricing,
    ).observation;
  assertEquals(run("Oldname example").mapping, {
    status: "matched",
    match: "synonym",
  });
  const genus = run("Syntheticus");
  assert(genus.prediction.outcome === "normalized");
  assertEquals(genus.prediction.taxon?.rank, "genus");
  for (
    const name of ["Unknownus example", "Unknownus", "Syntheticus examples"]
  ) {
    const v = run(name);
    assert(v.prediction.outcome === "normalized");
    assertEquals(v.prediction.resolution, "named");
    assertEquals(v.prediction.taxon, null);
    assertEquals(v.mapping?.status, "unmapped");
  }
  f.taxonomy.taxa[1].synonyms.push("Oldname example");
  assertEquals(
    resolveTaxon(parseTaxonomy(f.taxonomy), "Oldname example").mapping.status,
    "ambiguous",
  );
  const ambiguous = run("Oldname example");
  assert(ambiguous.prediction.outcome === "normalized");
  assertEquals(ambiguous.prediction.taxon, null);
  assertEquals(ambiguous.mapping?.status, "ambiguous");
  for (
    const patch of [{ returnedModel: "gpt-6-sol-unreviewed" }, {
      serviceTier: null,
    }]
  ) {
    const rejected = projectConfidenceOutcome(
      c.input.caseId,
      { ...outcome, ...patch },
      f.taxonomy,
      f.pricing,
    );
    assertEquals(rejected.observation.prediction.outcome, "invalid_output");
    assertEquals(rejected.settledNanoUsd, null);
  }
});

Deno.test("confidence denominators retain unresolved references, unsupported specificity, controls, mapping and every technical outcome", () => {
  const { corpus, observations } = confidenceFixture();
  const rows = confidenceRows(corpus.cases, observations);
  const first = observations[0];
  assert(first.prediction.outcome === "normalized");
  const replace = (index: number, patch: object) => {
    const prior = observations[index];
    assert(prior.prediction.outcome === "normalized");
    observations[index] = {
      ...prior,
      prediction: { ...prior.prediction, ...patch },
    };
  };
  // A broader answer is wrong until that precise canonical ID/rank is preaccepted.
  replace(0, { taxon: { id: "synthetic:genus", rank: "genus" } });
  assertEquals(confidenceRows(corpus.cases, observations)[0].correct, false);
  corpus.cases[0].reference = {
    ...corpus.cases[0].reference,
    acceptableTaxa: [...corpus.cases[0].reference.acceptableTaxa, {
      id: "synthetic:genus",
      rank: "genus",
    }],
  };
  assertEquals(confidenceRows(corpus.cases, observations)[0].correct, true);
  // Known source species still fails a genus-only evidence reference.
  replace(40, { taxon: { id: "synthetic:species", rank: "species" } });
  replace(50, {
    resolution: "named",
    taxon: { id: "synthetic:species", rank: "species" },
  });
  observations[50].mapping = { status: "matched", match: "canonical" };
  replace(80, {
    subject: "biological",
    resolution: "named",
    taxon: { id: "synthetic:species", rank: "species" },
  });
  observations[80].mapping = { status: "matched", match: "canonical" };
  replace(1, { taxon: null });
  observations[1].mapping = { status: "ambiguous", match: null };
  replace(2, { resolution: "unresolved", taxon: null });
  observations[2].mapping = { status: "not_applicable", match: null };
  for (
    const [i, outcome] of [
      "refusal",
      "invalid_output",
      "operational_failure",
      "unknown_execution",
      "local_validation_failure",
    ].entries()
  ) {
    observations[i + 3] = {
      prediction: {
        caseId: corpus.cases[i + 3].input.caseId,
        outcome: outcome as "refusal",
      },
      mapping: null,
    };
  }
  observations.splice(8, 1); // Unattempted is retained, not dropped.
  const report = confidenceSplitReport(
    confidenceRows(corpus.cases, observations).slice(0, 100),
    .61,
  );
  assertEquals(report.scheduled, 100);
  assertEquals(report.outcomes.unattempted, 1);
  assertEquals(report.namedPrecision.denominator, 65);
  assertEquals(report.namedPrecision.numerator, 61);
  assertEquals(report.strongErrors.numerator, 4);
  assertEquals(report.strongMappingFailures.numerator, 1);
  assertEquals(report.mappedStrongErrors.numerator, 3);
  assertEquals(report.mappedNamedErrors.numerator, 3);
  assertEquals(report.mappingFailures.numerator, 1);
  assertEquals(report.unsupportedSpecificity.numerator, 3);
  assertEquals(report.falseBiologicalAssertions.numerator, 1);
  assertEquals(report.appropriateAbstentions, confidenceRate(9, 10));
  assertEquals(report.biologicalAnswerCoverage.denominator, 80);
  assertEquals(report.returnedRanks.ambiguous.namedPrecision.denominator, 1);
  assertEquals(report.strongCoverage.denominator, 100);
  assertEquals(
    report.bins.reduce((n, b) => n + b.correctness.denominator, 0),
    65,
  );
  assertEquals(
    confidenceSplitReport(rows.slice(0, 100), .61).correctAnswerYield,
    confidenceRate(70, 80),
  );
});

Deno.test("raw scores drive fixed bins and cutoff boundaries before display rounding", () => {
  const { corpus, observations } = confidenceFixture();
  const scores = [0, .599, .60, .699, .70, .799, .80, .899, .90, .949, .95, 1];
  const cases = corpus.cases.slice(0, scores.length),
    values = observations.slice(0, scores.length);
  values.forEach((v, i) => {
    assert(v.prediction.outcome === "normalized");
    v.prediction = { ...v.prediction, confidence: scores[i] };
  });
  const report = confidenceSplitReport(confidenceRows(cases, values), .95);
  assertEquals(report.bins.map((b) => b.correctness.denominator), [
    2,
    2,
    2,
    2,
    2,
    2,
  ]);
  assertEquals(report.strongPrecision.denominator, 2);
  assertEquals(P.cutoffs.length, 40);
  assertEquals(P.cutoffs[0], .61);
  assertEquals(P.cutoffs.at(-1), 1);
  assertEquals(confidencePolicy("openai_gpt_6_sol"), null); // Historical metrics stay disabled.
});

Deno.test("development selects once; incomplete, invalidated or failing validation retains .95 without validation search", () => {
  const f = confidenceFixture();
  const selected = selectConfidenceCutoff(
    confidenceRows(f.corpus.cases, f.observations).slice(0, 100),
  );
  assertEquals(selected, .61);
  const reference = { ...f.corpus, kind: "reference" as const };
  assertEquals(
    confidenceAssessment(reference, f.observations, selected).recommendedStrong,
    .61,
  );
  assertEquals(
    confidenceAssessment(f.corpus, f.observations, selected).recommendedStrong,
    .95,
  );
  assertEquals(
    confidenceAssessment(reference, f.observations.slice(0, 199), selected)
      .decision,
    "validation_incomplete",
  );
  assertEquals(
    confidenceAssessment(reference, f.observations, null).recommendedStrong,
    .95,
  );
  assertEquals(
    confidenceAssessment(
      { ...reference, referenceStatus: "invalidated" },
      f.observations,
      selected,
    ).decision,
    "reference_invalidated",
  );
  for (let i = 100; i < 110; i++) {
    const v = f.observations[i];
    assert(v.prediction.outcome === "normalized");
    v.prediction = {
      ...v.prediction,
      taxon: { id: "synthetic:other", rank: "species" },
    };
  }
  const failed = confidenceAssessment(reference, f.observations, selected);
  assertEquals(failed.recommendedStrong, .95);
  assertEquals(failed.selectedCutoff, .61);
  assertEquals(failed.decision, "validation_failed");
  assertThrows(() => confidenceAssessment(reference, f.observations, .62));
  assertEquals(
    selectConfidenceCutoff(confidenceRows(f.corpus.cases, []).slice(0, 100)),
    null,
  );
  const rates = confidenceRate(38, 40);
  assertAlmostEquals(rates.value!, .95);
  assertAlmostEquals(rates.interval!.lower, .8349612, 1e-6);
  assert(rates.interval!.lower < .95);
  assertEquals(confidenceRate(0, 0), {
    numerator: 0,
    denominator: 0,
    value: null,
    interval: null,
    status: "not_estimable",
  });
});
