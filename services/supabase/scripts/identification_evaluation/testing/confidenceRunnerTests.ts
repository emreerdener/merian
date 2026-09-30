import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import { prepareConfidenceStudy } from "../confidencePreparation.ts";
import {
  executeConfidenceStudy,
  saveConfidenceReport,
} from "../confidenceRunner.ts";
import { confidenceClaim, readConfidenceLedger } from "../confidenceLedger.ts";
import { fingerprintJson } from "../evidence.ts";
import { atomicJson, claimJson, exists, readJson } from "../files.ts";
import {
  confidenceOutcome,
  confidenceSource as source,
  writeConfidenceFixture,
} from "./confidenceFixtures.ts";
import { projectConfidenceOutcome } from "../confidenceProjection.ts";
import type { AIAdapter } from "../../../functions/_shared/ai/contracts.ts";
import { openAIConfidenceSnapshot } from "../../../functions/_shared/ai/openaiPhotoConfidence.ts";

export function registerConfidenceRunnerTests(scratch: string) {
  async function setup() {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "confidence-",
    });
    const fixture = await writeConfidenceFixture(root);
    const study = await prepareConfidenceStudy(root, source);
    return { root, fixture, study };
  }
  Deno.test("confidence runner freezes before held-out calls, reserves durably, runs 200 once and never logs media or model prose", async () => {
    const { root, study } = await setup();
    try {
      let calls = 0;
      const adapter: AIAdapter<ReturnType<typeof openAIConfidenceSnapshot>> = {
        provider: "openai",
        prepare: () => async () => {
          const index = calls++, c = study.cases[index];
          const ledger = await readConfidenceLedger(root, study);
          assertEquals(ledger.attempted, calls);
          assertEquals(
            ledger.observations.at(-1)?.prediction.outcome,
            "unknown_execution",
          );
          assertEquals(
            ledger.outstandingNanoUsd,
            study.manifest.assignments[index].reservationNanoUsd,
          );
          assert(
            ledger.settledNanoUsd + ledger.outstandingNanoUsd <= 10_000_000_000,
          );
          assertEquals(
            await exists(join(root, "confidence-selection.json")),
            index >= 100,
          );
          return confidenceOutcome(c);
        },
      };
      const report = await executeConfidenceStudy(
        root,
        source,
        "offline",
        adapter,
      );
      assertEquals(calls, 200);
      assertEquals(report.accounting.attempted, 200);
      assertEquals(report.accounting.costComplete, true);
      assertEquals(report.decision, "validation_passed");
      assertEquals(report.selectedCutoff, .61);
      assertEquals(report.recommendedStrong, .95);
      assertEquals(report.thresholdDecisionEligible, false);
      assertEquals(report.development.namedPrecision.numerator, 70);
      assertEquals(report.validation.namedPrecision.denominator, 70);
      await executeConfidenceStudy(root, source, "offline", adapter);
      assertEquals(calls, 200);
      const journal = join(root, "confidence-attempts");
      for await (const e of Deno.readDir(journal)) {
        const text = JSON.stringify(await readJson(join(journal, e.name)));
        for (
          const forbidden of [
            "Syntheticus",
            "Synthetic organism",
            "data:image",
            "ai_reasoning",
            "secret",
          ]
        ) {
          assert(!text.includes(forbidden));
        }
      }
      const selection = await readJson(
        join(root, "confidence-selection.json"),
      ) as Record<string, unknown>;
      await atomicJson(join(root, "confidence-selection.json"), {
        ...selection,
        cutoff: .62,
      });
      await assertRejects(() =>
        executeConfidenceStudy(root, source, "offline", adapter)
      );
      assertEquals(calls, 200);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("confidence resume retains interrupted claims and uncertain billing, reconciles without retry or budget reset", async () => {
    const { root, study } = await setup();
    try {
      let calls = 0;
      const interrupted: AIAdapter<
        ReturnType<typeof openAIConfidenceSnapshot>
      > = {
        provider: "openai",
        prepare: () => () => {
          calls++;
          throw new Error("synthetic interruption");
        },
      };
      const report = await executeConfidenceStudy(
        root,
        source,
        "offline",
        interrupted,
      );
      assertEquals(calls, 1);
      assertEquals(report.stop, "uncertain_execution");
      assertEquals(report.development.outcomes.unknown_execution, 1);
      assertEquals(
        report.accounting.outstandingNanoUsd,
        study.manifest.assignments[0].reservationNanoUsd,
      );
      const resumed = await executeConfidenceStudy(
        root,
        source,
        "offline",
        interrupted,
      );
      assertEquals(calls, 1);
      assertEquals(resumed.stop, "accounting_reconciliation_required");
      const base = join(
        root,
        "confidence-attempts",
        study.cases[0].input.caseId,
      );
      await claimJson(base + ".reconciliation.json", {
        version: "openai_confidence_reconciliation_v1",
        claimDigest: await fingerprintJson(confidenceClaim(study, 0)),
        billingEvidenceRef: "synthetic-receipt",
        reviewRef: "synthetic-review",
        settledNanoUsd: 100,
      });
      await executeConfidenceStudy(root, source, "offline", interrupted);
      assertEquals(calls, 2); // Next observation, never the uncertain first one.
      const after = await readConfidenceLedger(root, study);
      assertEquals(after.attempted, 2);
      assertEquals(after.settledNanoUsd, 100);
      assertEquals(
        after.observations.map((v) => v.prediction.caseId),
        study.cases.slice(0, 2).map((c) => c.input.caseId),
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("confidence accounting blocks missing or contradictory usage, failed calls and model/tier mismatches", async () => {
    const { root, study, fixture } = await setup();
    try {
      const good = confidenceOutcome(study.cases[0]);
      assert(good.usage);
      for (
        const patch of [
          { usage: null },
          { usage: { ...good.usage, thinkingTokens: null } },
          { usage: { ...good.usage, totalTokens: 141 } },
          { usage: { ...good.usage, cachedTokens: 101 } },
          { returnedModel: "other" },
          { serviceTier: null },
          { kind: "unknown_execution" as const },
          { kind: "operational_failure" as const },
        ]
      ) {
        assertEquals(
          projectConfidenceOutcome(
            study.cases[0].input.caseId,
            { ...good, ...patch },
            fixture.taxonomy,
            fixture.pricing,
          ).settledNanoUsd,
          null,
        );
      }
      assertEquals(
        projectConfidenceOutcome(
          study.cases[0].input.caseId,
          good,
          fixture.taxonomy,
          fixture.pricing,
        ).settledNanoUsd,
        180_000,
      );
      let calls = 0;
      const adapter: AIAdapter<ReturnType<typeof openAIConfidenceSnapshot>> = {
        provider: "openai",
        prepare: () => () => {
          calls++;
          return Promise.resolve({ ...good, usage: null });
        },
      };
      const report = await executeConfidenceStudy(
        root,
        source,
        "offline",
        adapter,
      );
      assertEquals(calls, 1);
      assertEquals(report.accounting.attempted, 1);
      assertEquals(report.stop, "accounting_reconciliation_required");
      await executeConfidenceStudy(root, source, "offline", adapter);
      assertEquals(calls, 1);
      await assertRejects(() =>
        prepareConfidenceStudy(root, { ...source, digest: "2".repeat(64) })
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("confidence cost guard includes the next reservation and stops without replacement requests", async () => {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "confidence-budget-",
    });
    try {
      const fixture = await writeConfidenceFixture(root);
      fixture.pricing.models[0].inputPerMillion = {
        text: 9,
        image: 9,
        cached: 9,
        cacheWrite: 9,
      };
      fixture.pricing.models[0].outputPerMillion = 10;
      await atomicJson(join(root, "pricing.json"), fixture.pricing);
      const study = await prepareConfidenceStudy(root, source);
      let calls = 0;
      const adapter: AIAdapter<ReturnType<typeof openAIConfidenceSnapshot>> = {
        provider: "openai",
        prepare: () => () => {
          calls++;
          const good = confidenceOutcome(study.cases[0]);
          return Promise.resolve({
            ...good,
            usage: {
              ...good.usage!,
              promptTokens: 100000,
              candidateTokens: 7990,
              thinkingTokens: 10,
              totalTokens: 108000,
            },
          });
        },
      };
      const report = await executeConfidenceStudy(
        root,
        source,
        "offline",
        adapter,
      );
      assertEquals(calls, 1);
      assertEquals(report.accounting.settledNanoUsd, 980_000_000);
      assertEquals(report.stop, "budget_exhausted");
      assertEquals(report.development.outcomes.unattempted, 99);
      await executeConfidenceStudy(root, source, "offline", adapter);
      assertEquals(calls, 1);
      await claimJson(join(root, "confidence-invalidation.json"), {
        version: "openai_confidence_invalidation_v1",
        manifestDigest: study.digest,
        reviewRef: "synthetic-invalidated-reference",
      });
      assertEquals(
        (await saveConfidenceReport(root, study)).decision,
        "reference_invalidated",
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
}
