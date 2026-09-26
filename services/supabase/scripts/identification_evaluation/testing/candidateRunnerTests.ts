import { main } from "../../evaluate_identification.ts";
import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { join } from "node:path";
import { createCandidateDemo } from "../candidateOffline.ts";
import { executeExperimentRun, prepareExperiment } from "../experiment.ts";
import { parseExperimentPlan } from "../experimentContracts.ts";
import { experimentOfflineOutcome } from "../experimentOffline.ts";
import { CALIBRATION_EXAMPLES } from "../explanationCalibration.ts";
import { atomicJson, readJson } from "../files.ts";
import { saveExperimentReport } from "../experimentReport.ts";
import {
  parseAttempt,
  parseManifest,
  parseRunSpec,
  type SourceIdentity,
} from "../runContracts.ts";
import { prepareRun } from "../runner.ts";
import { unavailableRatings } from "../explanationContracts.ts";
const source: SourceIdentity = {
  commit: "0".repeat(40),
  dirty: true,
  digest: "1".repeat(64),
  sdk: "npm:@google/genai@2.23.0",
};
export function registerCandidateTests(scratch: string) {
  const setup = async () => {
    const root = await Deno.makeTempDir({ dir: scratch, prefix: "candidate-" });
    const now = Date.now();
    const plan = await createCandidateDemo(root, source, now);
    const prepared = await prepareExperiment(root, source, now);
    const offlineOutcome = await experimentOfflineOutcome(
      root,
      prepared.inputs[0],
    );
    return {
      root,
      plan,
      prepared,
      now,
      dependencies: {
        offlineOutcome,
        now: () => now + 1,
        review: () =>
          Promise.resolve(structuredClone(CALIBRATION_EXAMPLES[0].expected)),
      },
    };
  };
  const assistantSetup = async () => {
    const value = await setup();
    const plan = parseExperimentPlan({
      ...value.plan,
      version: "identification_experiment_plan_v3",
      candidateDecision: "concise_explanation_latency_ai_review_v1",
      review: {
        ...value.plan.review,
        calibrationDigest: null,
        method: "assistant_local_v1",
        delegationRef: "synthetic-user-delegation",
      },
    });
    await atomicJson(join(value.root, "experiment.json"), plan);
    await Deno.remove(join(value.root, "review", "calibration.json"));
    return {
      ...value,
      plan,
      prepared: await prepareExperiment(value.root, source, value.now),
    };
  };
  Deno.test("delegated candidate review needs no owner certificate and reports its own evidence class", async () => {
    const { root, plan, prepared, dependencies } = await assistantSetup();
    try {
      assertThrows(() =>
        parseExperimentPlan({
          ...plan,
          version: "identification_experiment_plan_v2",
        })
      );
      assertThrows(() =>
        parseExperimentPlan({
          ...plan,
          review: { ...plan.review, calibrationDigest: "1".repeat(64) },
        })
      );
      assertThrows(() =>
        parseExperimentPlan({
          ...plan,
          candidateDecision: "concise_explanation_latency_v1",
        })
      );
      for (const run of plan.runs) {
        assertEquals(
          (await executeExperimentRun(root, run.runId, source, dependencies))
            .stop,
          null,
        );
      }
      const report = await saveExperimentReport(root);
      assertEquals(report.version, "identification_experiment_report_v3");
      assertEquals(report.complete, true);
      assertEquals(report.evidenceStatus, "synthetic_mechanics_only");
      assertEquals(report.explanationReview?.method, "synthetic_fixture_v1");
      assertEquals(report.explanationReview?.independentHumanValidation, false);
      assertEquals(report.explanationReview?.additionalJudgeCalls, 0);
      assertEquals(report.productionQualified, false);
      assert(
        report.explanationAssessments?.every(({ record }) =>
          record.version === "explanation_assessment_v2" &&
          record.binding.calibrationDigest === null &&
          record.method === "synthetic_fixture_v1"
        ),
      );
      await Deno.remove(join(root, "assets"), { recursive: true });
      await Deno.remove(join(root, "review"), { recursive: true });
      assertEquals(await saveExperimentReport(root), report);
      const a = prepared.inputs[0].manifest.order[0];
      const path = join(
        root,
        "experiment",
        "assessments",
        plan.runs[0].runId,
        `${a.key}.json`,
      );
      const saved = await readJson(path) as Record<string, unknown>;
      await atomicJson(path, { ...saved, method: "owner_local_v1" });
      await assertRejects(() => saveExperimentReport(root));
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("delegated review still stops before another call on missing or failing assessment", async (t) => {
    for (const missing of [true, false]) {
      await t.step(missing ? "missing" : "unassessable", async () => {
        const { root, plan, dependencies } = await assistantSetup();
        try {
          let calls = 0;
          const d = {
            ...dependencies,
            offlineOutcome: (
              ...a: Parameters<typeof dependencies.offlineOutcome>
            ) => {
              calls++;
              return dependencies.offlineOutcome(...a);
            },
            review: () =>
              Promise.resolve(missing ? null : unavailableRatings()),
          };
          const result = await executeExperimentRun(
            root,
            plan.runs[0].runId,
            source,
            d,
          );
          assertEquals(result.stop, "explanation_quality_failed");
          await executeExperimentRun(root, plan.runs[1].runId, source, d);
          assertEquals(calls, 1);
          assertEquals((await saveExperimentReport(root)).complete, false);
        } finally {
          await Deno.remove(root, { recursive: true });
        }
      });
    }
  });
  Deno.test("candidate experiment completes with bound private assessments and historical parsers unchanged", async () => {
    const { root, plan, prepared, dependencies } = await setup();
    try {
      const manifest = prepared.inputs[0].manifest;
      assertEquals(manifest.version, "identification_provider_run_v2");
      assertThrows(() =>
        parseRunSpec({
          ...manifest.spec,
          version: "identification_provider_run_spec_v1",
        })
      );
      assertThrows(() =>
        parseManifest({
          ...manifest,
          version: "identification_provider_run_v1",
        })
      );
      assertThrows(() =>
        parseExperimentPlan({
          ...plan,
          version: "identification_experiment_plan_v1",
        })
      );
      await assertRejects(() => prepareRun(root, source, "offline"));
      let reviews = 0;
      for (const run of plan.runs) {
        assertEquals(
          (await executeExperimentRun(root, run.runId, source, {
            ...dependencies,
            review: (display) => {
              assert(display);
              assert(!JSON.stringify(display).includes("profileId"));
              reviews++;
              return dependencies.review();
            },
          })).stop,
          null,
        );
      }
      assertEquals(reviews, 8);
      const report = await saveExperimentReport(root);
      assertEquals(report.version, "identification_experiment_report_v2");
      assertEquals(report.complete, true);
      assertEquals(report.screeningDecision, "synthetic_mechanics_only");
      assertEquals(report.cacheComparability, "verified_zero_reads_and_writes");
      assertEquals(report.explanationAssessments?.length, 8);
      const first = manifest.order[0];
      const record = parseAttempt(
        await readJson(
          join(
            root,
            "runs",
            plan.runs[0].runId,
            "results",
            `${first.key}.json`,
          ),
        ),
      );
      assertEquals(record.version, "evaluation_openai_attempt_v3");
      assertThrows(() =>
        parseAttempt({ ...record, version: "evaluation_openai_attempt_v2" })
      );
      const saved = JSON.stringify(report);
      assert(!saved.includes("Invented offline fixture."));
      assert(!saved.includes("Invented fixture observation."));
      await Deno.remove(join(root, "assets"), { recursive: true });
      await Deno.remove(join(root, "review"), { recursive: true });
      assertEquals((await saveExperimentReport(root)).complete, true);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("candidate CLI produces a synthetic report and regenerates it without private content", async () => {
    const parent = await Deno.makeTempDir({
      dir: scratch,
      prefix: "candidate-cli-",
    });
    const root = join(parent, "packet");
    try {
      await main(["demo-candidate", root]);
      const report = await readJson(join(root, "experiment-report.json")) as {
        complete: boolean;
        screeningDecision: string;
      };
      assertEquals(report.complete, true);
      assertEquals(report.screeningDecision, "synthetic_mechanics_only");
      await main(["experiment-preflight", root]);
      await Deno.remove(join(root, "assets"), { recursive: true });
      await Deno.remove(join(root, "review"), { recursive: true });
      await main(["experiment-report", root]);
      assertEquals(
        await readJson(join(root, "experiment-report.json")),
        report,
      );
      await main(["report", root, "offline-concise-1"]);
      await main(["report", root, "offline-concise-2"]);
    } finally {
      await Deno.remove(parent, { recursive: true });
    }
  });
  Deno.test("candidate cache anomalies and failed or missing review stop all runs without replay", async (t) => {
    for (
      const kind of [
        "cache_missing",
        "cache_hit",
        "cache_write",
        "review_missing",
        "review_failed",
        "review_throw",
      ] as const
    ) {
      await t.step(kind, async () => {
        const { root, plan, dependencies } = await setup();
        try {
          let calls = 0;
          const d = {
            ...dependencies,
            offlineOutcome: (
              ...args: Parameters<typeof dependencies.offlineOutcome>
            ) => {
              calls++;
              const o = dependencies.offlineOutcome(...args);
              return {
                ...o,
                usage: {
                  ...o.usage!,
                  ...(kind === "cache_missing"
                    ? { cacheWriteTokens: null }
                    : {}),
                  ...(kind === "cache_hit" ? { cachedTokens: 1 } : {}),
                  ...(kind === "cache_write" ? { cacheWriteTokens: 1 } : {}),
                },
              };
            },
            review: async () => {
              if (kind === "review_throw") throw Error("synthetic");
              if (kind === "review_missing") return null;
              if (kind === "review_failed") return unavailableRatings();
              return await dependencies.review();
            },
          };
          const state = await executeExperimentRun(
            root,
            plan.runs[0].runId,
            source,
            d,
          );
          assert(state.stop);
          assertEquals(state.calls, 1);
          assertEquals(state.reservedCalls, 0);
          await executeExperimentRun(root, plan.runs[1].runId, source, d);
          assertEquals(calls, 1);
          assertEquals((await saveExperimentReport(root)).complete, false);
        } finally {
          await Deno.remove(root, { recursive: true });
        }
      });
    }
  });
  Deno.test("candidate crash after settlement preserves completed provider result and blocks recovery replay", async () => {
    const { root, plan, prepared, dependencies } = await setup();
    try {
      let calls = 0;
      const d = {
        ...dependencies,
        offlineOutcome: (
          ...a: Parameters<typeof dependencies.offlineOutcome>
        ) => {
          calls++;
          return dependencies.offlineOutcome(...a);
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
        dependencies,
      );
      assertEquals(state.stop, "explanation_review_missing");
      assertEquals(state.reservedCalls, 0);
      assertEquals(calls, 1);
      const a = prepared.inputs[0].manifest.order[0];
      const result = parseAttempt(
        await readJson(
          join(root, "runs", plan.runs[0].runId, "results", `${a.key}.json`),
        ),
      );
      assertEquals(result.prediction.outcome, "normalized");
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("candidate facts, calibration and assessment binding tampering fail closed", async () => {
    const { root, plan, dependencies } = await setup();
    try {
      const facts = await readJson(join(root, "review", "facts.json")) as {
        cards: { observed: string[] }[];
      };
      facts.cards[0].observed = ["changed fact"];
      await atomicJson(join(root, "review", "facts.json"), facts);
      await assertRejects(() => prepareExperiment(root, source));
    } finally {
      await Deno.remove(root, { recursive: true });
    }
    const next = await setup();
    try {
      await executeExperimentRun(
        next.root,
        next.plan.runs[0].runId,
        source,
        next.dependencies,
      );
      const a = next.prepared.inputs[0].manifest.order[0];
      const path = join(
        next.root,
        "experiment",
        "assessments",
        next.plan.runs[0].runId,
        `${a.key}.json`,
      );
      const assessment = await readJson(path) as {
        binding: { resultDigest: string };
      };
      assessment.binding.resultDigest = "0".repeat(64);
      await atomicJson(path, assessment);
      await assertRejects(() => saveExperimentReport(next.root));
    } finally {
      await Deno.remove(next.root, { recursive: true });
    }
    void plan;
    void dependencies;
  });
}
