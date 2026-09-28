import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { join } from "node:path";
import { main } from "../../evaluate_identification.ts";
import { createNullFieldsDemo } from "../nullFieldsOffline.ts";
import { validateSelectionFacts } from "../admission.ts";
import { executeExperimentRun, prepareExperiment } from "../experiment.ts";
import {
  EXPERIMENT_METRICS,
  parseExperimentPlan,
} from "../experimentContracts.ts";
import { experimentOfflineOutcome } from "../experimentOffline.ts";
import { fingerprintRunCorpus } from "../exploratory.ts";
import { CALIBRATION_EXAMPLES } from "../explanationCalibration.ts";
import { unavailableRatings } from "../explanationContracts.ts";
import { atomicJson, readJson } from "../files.ts";
import { saveExperimentReport } from "../experimentReport.ts";
import {
  parseAttempt,
  parseManifest,
  parseRunSpec,
  type SourceIdentity,
} from "../runContracts.ts";
import { executeRun, prepareRun } from "../runner.ts";

const source: SourceIdentity = {
  commit: "0".repeat(40),
  dirty: true,
  digest: "1".repeat(64),
  sdk: "npm:@google/genai@2.23.0",
};
export function registerNullFieldsTests(scratch: string) {
  const setup = async () => {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "null-fields-",
    });
    const now = Date.now();
    const plan = await createNullFieldsDemo(root, source, now);
    const prepared = await prepareExperiment(root, source, now);
    return {
      root,
      plan,
      prepared,
      now,
      dependencies: {
        now: () => now + 1,
        offlineOutcome: await experimentOfflineOutcome(
          root,
          prepared.inputs[0],
        ),
        review: () =>
          Promise.resolve(structuredClone(CALIBRATION_EXAMPLES[0].expected)),
      },
    };
  };
  Deno.test("null-field experiment keeps strict old versions and enforces the six-photo allocation", async () => {
    const { root, plan, prepared } = await setup();
    try {
      for (
        const invalid of [
          { version: "identification_experiment_plan_v1" },
          { version: "identification_experiment_plan_v2" },
          { version: "identification_experiment_plan_v3" },
          { cacheControl: "explicit_no_breakpoints_v1" },
          { metrics: EXPERIMENT_METRICS },
          { candidateDecision: "concise_explanation_latency_ai_review_v1" },
          { maxCalls: plan.maxCalls + 1 },
          { runs: plan.runs.toReversed() },
          {
            runs: [plan.runs[0], {
              ...plan.runs[1],
              pricingDigest: "2".repeat(64),
            }],
          },
          { review: { ...plan.review, calibrationDigest: "1".repeat(64) } },
        ]
      ) assertThrows(() => parseExperimentPlan({ ...plan, ...invalid }));
      const { review: _review, ...withoutReview } = plan;
      assertThrows(() =>
        parseExperimentPlan({
          ...withoutReview,
          version: "identification_experiment_plan_v1",
          metrics: EXPERIMENT_METRICS,
          candidateDecision: "deferred_cache_isolation_and_explanation_rubric",
        })
      );
      const cases = Array.from({ length: 6 }, (_, i) => ({
        caseId: "c" + String(i + 1).padStart(4, "0"),
        inputDigest: String(i + 1).repeat(64),
      }));
      const live = {
        ...plan,
        mode: "live",
        cases,
        maxCalls: 12,
        runs: plan.runs.map((r) => ({
          ...r,
          maxCalls: 6,
          readinessDigest: "1".repeat(64),
        })),
      };
      assertEquals(parseExperimentPlan(live).cases.length, 6);
      assertThrows(() =>
        parseExperimentPlan({
          ...live,
          cases: cases.slice(1),
          maxCalls: 10,
          runs: live.runs.map((r) => ({ ...r, maxCalls: 5 })),
        })
      );
      const manifest = prepared.inputs[1].manifest;
      assertEquals(manifest.version, "identification_provider_run_v3");
      assertEquals(
        manifest.spec.version,
        "identification_provider_run_spec_v3",
      );
      for (
        const version of [
          "identification_provider_run_spec_v1",
          "identification_provider_run_spec_v2",
        ]
      ) {
        assertThrows(() => parseRunSpec({ ...manifest.spec, version }));
      }
      assertThrows(() =>
        parseManifest({
          ...manifest,
          version: "identification_provider_run_v2",
        })
      );
      await assertRejects(() => prepareRun(root, source, "offline"));
      await assertRejects(() => executeRun(root, prepared.inputs[1]));
      // Even stripped of its experiment, the candidate cannot enter standalone admission.
      await Deno.remove(join(root, "experiment.json"));
      await atomicJson(join(root, "spec.json"), manifest.spec);
      await assertRejects(() => prepareRun(root, source, "offline"));
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("null-field controller rejects text-only evidence even in its baseline arm", async () => {
    const { root, prepared } = await setup();
    try {
      const { corpus, manifest, taxonomy } = prepared.inputs[0];
      assert(corpus.kind === "exploratory");
      const changed = {
        ...corpus,
        cases: corpus.cases.map((c, i) =>
          i > 0 ? c : {
            ...c,
            input: {
              ...c.input,
              inputGroup: "description" as const,
              assets: [],
              observationTexts: ["Invented observation."],
            },
          }
        ),
      };
      const spec = {
        ...manifest.spec,
        corpusDigest: await fingerprintRunCorpus(changed),
      };
      await assertRejects(() =>
        validateSelectionFacts(changed, spec, taxonomy)
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("null-field review accepts baseline cache observations, retains new record identities and never replays", async (t) => {
    for (const writes of [5, null]) {
      await t.step(
        writes === null ? "unknown writes" : "cache reads and writes",
        async () => {
          const { root, plan, prepared, dependencies } = await setup();
          try {
            let calls = 0;
            const d = {
              ...dependencies,
              offlineOutcome: (
                ...args: Parameters<typeof dependencies.offlineOutcome>
              ) => {
                calls++;
                const outcome = dependencies.offlineOutcome(...args);
                return {
                  ...outcome,
                  usage: {
                    ...outcome.usage!,
                    cachedTokens: 20,
                    cacheWriteTokens: writes,
                  },
                };
              },
            };
            for (const run of plan.runs) {
              const state = await executeExperimentRun(
                root,
                run.runId,
                source,
                d,
              );
              assertEquals(state.stop, null);
              assertEquals(state.reservedCalls, 0);
            }
            const report = await saveExperimentReport(root);
            assertEquals(calls, plan.maxCalls);
            assertEquals(report.version, "identification_experiment_report_v4");
            assertEquals(report.complete, true);
            assertEquals(report.cacheComparability, "not_established");
            assertEquals(
              report.performanceInterpretation,
              "descriptive_only_uncontrolled_cache",
            );
            assertEquals(report.metrics.thresholdPercent, null);
            assertEquals(report.productionQualified, false);
            assertEquals(report.screeningDecision, "synthetic_mechanics_only");
            assertEquals(report.explanationAssessments?.length, plan.maxCalls);
            assertEquals(
              report.explanationReview?.independentHumanValidation,
              false,
            );
            assert(
              report.explanationAssessments!.every((a) =>
                a.record.version === "explanation_assessment_v2"
              ),
            );
            for (const slice of report.comparisons[0].slices) {
              assertEquals(slice.observedLatencyImprovementPercent, null);
              assertEquals(slice.observedCostImprovementPercent, null);
              assertEquals(slice.costMeasurementsComparable, false);
            }
            for (
              const [i, expected] of [
                "evaluation_openai_attempt_v2",
                "evaluation_openai_attempt_v4",
              ].entries()
            ) {
              const a = prepared.inputs[i].manifest.order[0];
              const record = parseAttempt(
                await readJson(
                  join(
                    root,
                    "runs",
                    plan.runs[i].runId,
                    "results",
                    a.key + ".json",
                  ),
                ),
              );
              assertEquals(record.version, expected);
              assertEquals(record.usage?.cacheWriteTokens, writes);
              assertThrows(() =>
                parseAttempt({
                  ...record,
                  version: i === 0
                    ? "evaluation_openai_attempt_v4"
                    : "evaluation_openai_attempt_v2",
                })
              );
              assertThrows(() =>
                parseAttempt({
                  ...record,
                  version: "evaluation_openai_attempt_v3",
                })
              );
            }
            for (const run of plan.runs) {
              await executeExperimentRun(root, run.runId, source, d);
            }
            assertEquals(calls, plan.maxCalls);
            const serialized = JSON.stringify(report);
            assert(!serialized.includes("Invented fixture observation."));
            assert(!serialized.includes("Invented offline fixture."));
            await Deno.remove(join(root, "review"), { recursive: true });
            await Deno.remove(join(root, "assets"), { recursive: true });
            assertEquals(await saveExperimentReport(root), report);
          } finally {
            await Deno.remove(root, { recursive: true });
          }
        },
      );
    }
  });
  Deno.test("null-field unknown billable usage and failed review stop before another call", async (t) => {
    for (const problem of ["usage", "review"] as const) {
      await t.step(problem, async () => {
        const { root, plan, dependencies } = await setup();
        try {
          let calls = 0;
          const d = {
            ...dependencies,
            offlineOutcome: (
              ...args: Parameters<typeof dependencies.offlineOutcome>
            ) => {
              calls++;
              const outcome = dependencies.offlineOutcome(...args);
              return {
                ...outcome,
                usage: problem === "usage" ? null : outcome.usage,
              };
            },
            review: problem === "review"
              ? () => Promise.resolve(unavailableRatings())
              : dependencies.review,
          };
          const state = await executeExperimentRun(
            root,
            plan.runs[0].runId,
            source,
            d,
          );
          assertEquals(
            state.stop,
            problem === "usage"
              ? "usage_missing"
              : "explanation_quality_failed",
          );
          assertEquals(state.reservedCalls, problem === "usage" ? 1 : 0);
          await executeExperimentRun(root, plan.runs[1].runId, source, d);
          assertEquals(calls, 1);
          const report = await saveExperimentReport(root);
          assertEquals(report.complete, false);
          assertEquals(report.productionQualified, false);
        } finally {
          await Deno.remove(root, { recursive: true });
        }
      });
    }
  });
  Deno.test("null-field interrupted review retains the completed result and stops without another invocation", async () => {
    const { root, plan, dependencies } = await setup();
    try {
      let calls = 0;
      const d = {
        ...dependencies,
        offlineOutcome: (
          ...args: Parameters<typeof dependencies.offlineOutcome>
        ) => {
          calls++;
          return dependencies.offlineOutcome(...args);
        },
        experimentCheckpoint: (point: string) => {
          if (point === "after_settlement") throw Error("synthetic crash");
        },
      };
      await assertRejects(() =>
        executeExperimentRun(root, plan.runs[0].runId, source, d)
      );
      const state = await executeExperimentRun(
        root,
        plan.runs[1].runId,
        source,
        d,
      );
      assertEquals(state.stop, "explanation_review_missing");
      assertEquals(calls, 1);
      assertEquals(state.reservedCalls, 0);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("null-field CLI runs a separate offline demo and regenerates its report without media", async () => {
    const parent = await Deno.makeTempDir({
      dir: scratch,
      prefix: "null-fields-cli-",
    });
    const root = join(parent, "packet");
    try {
      await main(["demo-null-fields", root]);
      await main(["experiment-preflight", root]);
      const report = await readJson(join(root, "experiment-report.json"));
      await Deno.remove(join(root, "assets"), { recursive: true });
      await Deno.remove(join(root, "review"), { recursive: true });
      await main(["experiment-report", root]);
      assertEquals(
        await readJson(join(root, "experiment-report.json")),
        report,
      );
      for (const id of ["offline-null-fields-1", "offline-null-fields-2"]) {
        await main(["report", root, id]);
      }
    } finally {
      await Deno.remove(parent, { recursive: true });
    }
  });
}
