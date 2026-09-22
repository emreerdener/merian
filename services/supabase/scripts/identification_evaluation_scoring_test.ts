import {
  assertAlmostEquals,
  assertEquals,
  assertRejects,
  assertThrows,
} from "@std/assert";
import type { Prediction } from "./identification_evaluation/contracts.ts";
import {
  syntheticCorpus,
  syntheticPredictions,
} from "./identification_evaluation/fixtures.ts";
import { rate, scoreEvaluation } from "./identification_evaluation/scoring.ts";
import { EvaluationContractError } from "./identification_evaluation/validation.ts";

const scope = { profile: "gemini_flash_free", split: "development" } as const;

Deno.test("hand-worked synthetic scores keep failures, negatives and unknowns in denominators", async () => {
  const report = await scoreEvaluation(
    syntheticCorpus(),
    syntheticPredictions(),
    scope,
  );
  assertEquals(report.counts, {
    scheduled: 12,
    biological: 10,
    speciesAnswerable: 7,
    named: 5,
    unsupportedSpecificity: 3,
    unresolvedMapping: 0,
  });
  assertEquals(report.outcomes, {
    normalized: 7,
    refusal: 1,
    invalid_output: 1,
    operational_failure: 1,
    unknown_execution: 1,
    local_validation_failure: 0,
    unattempted: 1,
  });
  assertEquals(report.metrics, {
    exactSpecies: rate(2, 7),
    offeredPrecision: rate(2, 5),
    answerCoverage: rate(4, 10),
    correctAnswerYield: rate(2, 10),
    subjectAccuracy: rate(6, 12),
    appropriateUnresolved: rate(2, 4),
    falseBiologicalAssertions: rate(1, 2),
    unsupportedBiologicalAssertions: rate(0, 0),
    strongErrorRate: rate(3, 12),
    strongErrorAmongNamed: rate(3, 4),
    diagnosticErrorRate: rate(2, 12),
    diagnosticErrorAmongNamed: rate(2, 3),
  });
  assertEquals(report.reliability.strong.correctness, rate(1, 4));
  assertAlmostEquals(report.reliability.strong.meanScore!, 0.985);
  assertEquals(report.reliability.possible.correctness, rate(1, 1));
  assertEquals(report.reliability.diagnostic_subset.correctness, rate(1, 3));
  assertEquals(report.subjectMatrix.non_biological.biological, 1);
  assertEquals(report.subjectMatrix.biological.no_result, 5);
  assertEquals(report.resolutionMatrix.unresolved.named, 2);
  assertEquals(report.verdict, "measurement_only");
  assertEquals(report.completeness, "incomplete");
  assertEquals(report.evidenceKind, "synthetic");
  assertEquals(report.performance, "not_measured");
  assertEquals(report.intervals, "not_computed");
  const json = JSON.stringify(report);
  for (
    const forbidden of [
      "synthetic:1",
      "Synthetic broad",
      "assets/",
      "reviewerRefs",
    ]
  ) assertEquals(json.includes(forbidden), false);
});

Deno.test("profile thresholds retain current Gemini Strong behavior", async () => {
  const report = await scoreEvaluation(
    syntheticCorpus(),
    syntheticPredictions(),
    { ...scope, profile: "gemini_pro" },
  );
  assertEquals(report.metrics.strongErrorAmongNamed, rate(3, 5));
  assertEquals(report.reliability.strong.correctness, rate(2, 5));
  assertAlmostEquals(report.reliability.strong.meanScore!, 0.968);
  assertEquals(report.metrics.exactSpecies, rate(2, 7));
});

Deno.test("zero-denominator metrics are explicitly not estimable", () => {
  assertEquals(rate(0, 0), {
    numerator: 0,
    denominator: 0,
    value: null,
    status: "not_estimable",
  });
  assertThrows(() => rate(1, 0), EvaluationContractError);
  assertThrows(() => rate(-1, 2), EvaluationContractError);
});

Deno.test("all-abstaining and all-failed outputs cannot earn identity or uncertainty credit", async () => {
  const corpus = syntheticCorpus();
  const failures = corpus.cases.map((item): Prediction => ({
    caseId: item.input.caseId,
    outcome: "refusal",
  }));
  const failed = await scoreEvaluation(corpus, failures, scope);
  assertEquals(failed.metrics.exactSpecies, rate(0, 7));
  assertEquals(failed.metrics.offeredPrecision, rate(0, 0));
  assertEquals(failed.metrics.answerCoverage, rate(0, 10));
  assertEquals(failed.metrics.appropriateUnresolved, rate(0, 4));
  assertEquals(failed.completeness, "complete"); // Complete measurement, not success.
  assertEquals(failed.verdict, "measurement_only");
  const abstentions = corpus.cases.map((item): Prediction => ({
    caseId: item.input.caseId,
    outcome: "normalized",
    subject: "biological",
    resolution: "unresolved",
    taxon: null,
    confidence: 0,
  }));
  const unknown = await scoreEvaluation(corpus, abstentions, scope);
  assertEquals(unknown.metrics.correctAnswerYield, rate(0, 10));
  assertEquals(unknown.metrics.appropriateUnresolved, rate(2, 4));
});

Deno.test("named answers with unresolved taxonomy mapping remain offered but unverified", async () => {
  const predictions = syntheticPredictions();
  predictions[0] = {
    caseId: "c0001",
    outcome: "normalized",
    subject: "biological",
    resolution: "named",
    taxon: null,
    confidence: 0.99,
  };
  const report = await scoreEvaluation(syntheticCorpus(), predictions, scope);
  assertEquals(report.counts.named, 5);
  assertEquals(report.counts.unresolvedMapping, 1);
  assertEquals(report.metrics.offeredPrecision, rate(1, 5));
  assertEquals(report.metrics.strongErrorAmongNamed, rate(4, 4));
});

Deno.test("genus answers receive only explicitly allowed rank credit", async () => {
  const predictions = syntheticPredictions();
  predictions[1] = {
    caseId: "c0002",
    outcome: "normalized",
    subject: "biological",
    resolution: "named",
    taxon: { id: "synthetic:2", rank: "genus" },
    confidence: 0.99,
  };
  const report = await scoreEvaluation(syntheticCorpus(), predictions, scope);
  assertEquals(report.metrics.offeredPrecision, rate(3, 5));
  assertEquals(report.metrics.exactSpecies, rate(2, 7));
  assertEquals(report.counts.unsupportedSpecificity, 2);
});

Deno.test("missing and explicit unattempted cases have identical incomplete scores", async () => {
  const predictions = syntheticPredictions();
  assertEquals(
    await scoreEvaluation(syntheticCorpus(), predictions.slice(0, -1), scope),
    await scoreEvaluation(syntheticCorpus(), predictions, scope),
  );
  const empty = await scoreEvaluation(syntheticCorpus(), [], {
    ...scope,
    split: "held_out",
  });
  assertEquals(empty.counts.scheduled, 0);
  assertEquals(empty.metrics.exactSpecies, rate(0, 0));
  assertEquals(empty.completeness, "incomplete");
});

Deno.test("scoring rejects extra cases, foreign splits and pooled repetitions", async () => {
  const predictions = syntheticPredictions();
  await assertRejects(
    () =>
      scoreEvaluation(
        syntheticCorpus(),
        [predictions[0], predictions[0]],
        scope,
      ),
    EvaluationContractError,
    "duplicate_prediction",
  );
  await assertRejects(
    () =>
      scoreEvaluation(syntheticCorpus(), [{
        caseId: "c9999",
        outcome: "refusal",
      }], scope),
    EvaluationContractError,
    "unknown_case",
  );
  await assertRejects(
    () =>
      scoreEvaluation(syntheticCorpus(), predictions, {
        ...scope,
        split: "held_out",
      }),
    EvaluationContractError,
    "unknown_case",
  );
});

Deno.test("input-group reports use their own fixed eligible populations", async () => {
  const report = await scoreEvaluation(
    syntheticCorpus(),
    syntheticPredictions(),
    { ...scope, inputGroup: "photos_audio" },
  );
  assertEquals(report.counts.scheduled, 2);
  assertEquals(report.counts.biological, 1);
  assertEquals(report.metrics.answerCoverage, rate(0, 1));
  assertEquals(report.metrics.offeredPrecision, rate(0, 1));
  assertEquals(report.metrics.strongErrorRate, rate(1, 2));
});

Deno.test("indeterminate subjects receive a separate unsupported-assertion rate", async () => {
  const source = syntheticCorpus();
  const cases = source.cases.map((item, index) =>
    index === 5
      ? {
        ...item,
        reference: {
          subject: "indeterminate" as const,
          resolution: "unresolved" as const,
          supportedRank: null,
          acceptableTaxa: [],
        },
      }
      : item
  );
  const report = await scoreEvaluation(
    { ...source, cases },
    syntheticPredictions(),
    scope,
  );
  assertEquals(report.metrics.falseBiologicalAssertions, rate(0, 1));
  assertEquals(report.metrics.unsupportedBiologicalAssertions, rate(1, 1));
  assertEquals(report.metrics.strongErrorRate, rate(3, 12));
  assertEquals(report.subjectMatrix.indeterminate.biological, 1);
});

Deno.test("unbalanced partial corpora are never labeled balanced", async () => {
  const source = syntheticCorpus();
  const report = await scoreEvaluation(
    { ...source, cases: source.cases.slice(0, 1) },
    syntheticPredictions().slice(0, 1),
    scope,
  );
  assertEquals(report.inputGroup, "all_cases");
  assertEquals(report.counts.scheduled, 1);
});
