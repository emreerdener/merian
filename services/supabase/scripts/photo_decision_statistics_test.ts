import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  decisionMetrics,
  decisionRows,
  pairedDecision,
  selectEvidenceCandidate,
} from "./identification_evaluation/photoDecisionStatistics.ts";
import { confidenceFixture } from "./identification_evaluation/testing/confidenceFixtures.ts";

Deno.test("photo primary credits correct names, abstentions and nonbiological rejections; missing outcomes fail", () => {
  const { corpus, observations } = confidenceFixture();
  const cases = corpus.cases.filter((c) => c.input.split === "development");
  const values = observations.filter((o) =>
    cases.some((c) => c.input.caseId === o.prediction.caseId)
  );
  assertEquals(
    decisionRows(cases, values).filter((r) => r.success).length,
    100,
  );
  assertEquals(decisionRows(cases, []).some((r) => r.success), false);
  assertEquals(decisionMetrics(cases, values).correctNamedYield.numerator, 70);
  const unresolved = cases.find((c) =>
    c.category === "limited" && c.reference.resolution === "unresolved"
  )!;
  const wrong = {
    prediction: {
      caseId: unresolved.input.caseId,
      outcome: "normalized" as const,
      subject: "biological" as const,
      resolution: "named" as const,
      taxon: null,
      confidence: 0.99,
    },
    mapping: { status: "unmapped" as const, match: null },
  };
  assertEquals(decisionRows([unresolved], [wrong])[0].success, false);
});

Deno.test("paired exact intervals remain uncertain with no discordance and tiny samples", () => {
  const identical = pairedDecision(
    Array(100).fill(true),
    Array(100).fill(true),
  );
  assertEquals(identical.effect, 0);
  assertEquals(identical.exactMcNemarP, 1);
  assert(
    identical.simultaneousPairedInterval.lower < 0 &&
      identical.simultaneousPairedInterval.upper > 0,
  );
  assertEquals(pairedDecision([false], [true]).superiority, false);
  assertThrows(() => pairedDecision([], []));
  assertThrows(() => pairedDecision([true], []));
});

Deno.test("paired discordant counts and symmetric confidence bounds support a large effect", () => {
  const a = Array.from({ length: 100 }, (_, i) => i < 50);
  const b = Array.from({ length: 100 }, (_, i) => i < 80);
  const forward = pairedDecision(a, b), reverse = pairedDecision(b, a);
  assertEquals(forward.challengerOnlyCorrect, 30);
  assertEquals(forward.controlOnlyCorrect, 0);
  assertEquals(forward.effect, .3);
  assertEquals(forward.superiority, true);
  assertEquals(forward.exactMcNemarP, 2 ** -29);
  assert(
    Math.abs(
      forward.simultaneousPairedInterval.lower +
        reverse.simultaneousPairedInterval.upper,
    ) < 1e-12,
  );
  assertEquals(reverse.superiority, false);
});

Deno.test("development selection requires actual nonmapping gain and limits species regressions", () => {
  const { corpus, observations } = confidenceFixture();
  const cases = corpus.cases.filter((c) =>
    c.input.split === "development" && c.reference.supportedRank === "species"
  ).slice(0, 20);
  const correct = observations.filter((o) =>
    cases.some((c) => c.input.caseId === o.prediction.caseId)
  );
  const unmapped = correct.map((o, i) =>
    i < 2 && o.prediction.outcome === "normalized"
      ? {
        prediction: { ...o.prediction, taxon: null },
        mapping: { status: "unmapped" as const, match: null },
      }
      : o
  );
  assertEquals(
    selectEvidenceCandidate(cases, unmapped, correct).selected,
    false,
  );
  const wrong = correct.map((o, i) =>
    i < 2 && o.prediction.outcome === "normalized"
      ? {
        ...o,
        prediction: {
          ...o.prediction,
          taxon: { id: "synthetic:other", rank: "species" as const },
        },
      }
      : o
  );
  assertEquals(selectEvidenceCandidate(cases, wrong, correct).selected, true);
  assertEquals(selectEvidenceCandidate(cases, [], correct).selected, false);
});
