import { fingerprintJson } from "../evidence.ts";
import {
  fingerprintRunCorpus,
  parseExploratoryCorpus,
} from "../exploratory.ts";
import { saveExperimentReport } from "../experimentReport.ts";
import { estimateCost } from "../profiles.ts";
import { parseAttempt, parseManifest } from "../runContracts.ts";
import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { join } from "node:path";
import { main } from "../../evaluate_identification.ts";
import { resolveAIClaim } from "../../../functions/_shared/ai/registry.ts";
import { createAIExecution } from "../../../functions/_shared/ai/execution.ts";
import { prepareEvidence } from "../assets.ts";
import {
  executeExperimentRun,
  type ExperimentDependencies,
  prepareExperiment,
} from "../experiment.ts";
import {
  budgetUnits,
  chargeUnits,
  experimentGuard,
  parseExperimentPlan,
} from "../experimentContracts.ts";
import {
  createExperimentDemo,
  experimentOfflineOutcome,
} from "../experimentOffline.ts";
import { atomicJson, exists, privateDirectory, readJson } from "../files.ts";
import { assignmentFor, fixtureAuthority, reserveCost } from "../profiles.ts";
import {
  executionProfile,
  REUSABLE_PROFILE_IDS,
  reusableAssignmentFor,
  reusableProfile,
} from "../reusableProfiles.ts";
import { executeRun, prepareRun } from "../runner.ts";
import type { SourceIdentity } from "../runContracts.ts";

const source: SourceIdentity = {
  commit: "0".repeat(40),
  dirty: true,
  digest: "1".repeat(64),
  sdk: "npm:@google/genai@2.23.0",
};
export function registerExperimentTests(scratch: string) {
  const setup = async () => {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "experiment-",
    });
    const now = Date.now();
    const plan = await createExperimentDemo(root, source, now);
    const prepared = await prepareExperiment(root, source, now);
    const offlineOutcome = await experimentOfflineOutcome(
      root,
      prepared.inputs[0],
    );
    const dependencies = { offlineOutcome, now: () => now + 1 };
    return { root, now, plan, prepared, dependencies };
  };

  Deno.test("experiment profiles freeze native baseline configuration and preserve request parity", async () => {
    const { root, plan, prepared } = await setup();
    try {
      const expected = [
        "0de814f2b9534e066175bc55b0d2cb26463bb3c3fc7dd0a3d46928596a8c6dc9",
        "b44c88586f48bde74d3b6f316b379160777d991860529c2089e4f64413939d01",
      ];
      for (const [i, id] of REUSABLE_PROFILE_IDS.slice(0, 2).entries()) {
        assertEquals((await reusableProfile(id)).digest, expected[i]);
        const inputs = prepared.inputs[i];
        for (const c of inputs.corpus.cases) {
          const request = await prepareEvidence(root, c.input);
          assertEquals(
            await reusableAssignmentFor(
              c.input,
              request,
              id,
              1,
              plan.runs[i].pricing,
            ),
            await assignmentFor(
              c.input,
              request,
              executionProfile(id),
              1,
              plan.runs[i].pricing,
            ),
          );
          await assertRejects(() =>
            reusableAssignmentFor(
              c.input,
              { ...request, capture: { ...request.capture, hasVideo: true } },
              id,
              1,
              null,
            )
          );
        }
      }
      await assertRejects(() =>
        reusableProfile(
          "unreviewed_candidate" as typeof REUSABLE_PROFILE_IDS[number],
        )
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });

  Deno.test("experiment completes frozen runs once and refuses standalone and forged-control bypasses", async () => {
    const { root, plan, prepared, dependencies } = await setup();
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
      };
      await assertRejects(
        () => prepareRun(root, source, "offline"),
        Error,
        "evaluation_experiment_required",
      );
      await assertRejects(
        () => executeRun(root, prepared.inputs[0], d),
        Error,
        "evaluation_experiment_required",
      );
      await assertRejects(() =>
        executeRun(root, prepared.inputs[0], d, {
          pricing: plan.runs[0].pricing,
          readinessPath: "unused",
          beforeClaim: () => Promise.resolve(null),
          afterResult: () => Promise.resolve(null),
        })
      );
      await assertRejects(() =>
        executeExperimentRun(root, plan.runs[1].runId, source, d)
      );
      assertEquals(calls, 0);
      const first = await executeExperimentRun(
        root,
        plan.runs[0].runId,
        source,
        d,
      );
      assertEquals(first.calls, 4);
      assertEquals(first.stop, null);
      assertEquals(first.reservedCalls, 0);
      assertEquals(first.completedRunIds, [plan.runs[0].runId]);
      const final = await executeExperimentRun(
        root,
        plan.runs[1].runId,
        source,
        d,
      );
      assertEquals(calls, 8);
      assertEquals(final.calls, 8);
      assertEquals(final.stop, null);
      assertEquals(final.chargedUnits, 8 * chargeUnits(110 / 1e6));
      assertEquals(final.completedRunIds, plan.runs.map((r) => r.runId));
      assertEquals(
        await executeExperimentRun(root, plan.runs[0].runId, source, d),
        final,
      );
      assertEquals(
        await executeExperimentRun(root, plan.runs[1].runId, source, d),
        final,
      );
      assertEquals(calls, 8);
      const frozen = JSON.stringify(
        await readJson(join(root, "experiment", "manifest.json")),
      );
      assert(
        !frozen.includes("credentialSha256") &&
          !frozen.includes("Synthetic configuration probe."),
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });

  Deno.test("experiment crash boundaries retain reservations or settle once and stop every later run", async (t) => {
    for (
      const point of [
        "before_claim",
        "after_reservation",
        "after_claim",
        "after_invoke",
        "after_result",
        "after_settlement",
      ] as const
    ) {
      await t.step(point, async () => {
        const { root, plan, prepared, dependencies } = await setup();
        try {
          let calls = 0;
          const d: ExperimentDependencies = {
            ...dependencies,
            offlineOutcome: (...args) => {
              calls++;
              return dependencies.offlineOutcome(...args);
            },
            checkpoint: (p) => {
              if (p === point) throw new Error("synthetic_crash");
            },
            experimentCheckpoint: (p) => {
              if (p === point) throw new Error("synthetic_crash");
            },
          };
          await assertRejects(
            () => executeExperimentRun(root, plan.runs[0].runId, source, d),
            Error,
            "synthetic_crash",
          );
          const before = calls;
          const state = await executeExperimentRun(
            root,
            plan.runs[1].runId,
            source,
            dependencies,
          );
          assert(state.stop !== null);
          assertEquals(state.calls, point === "before_claim" ? 0 : 1);
          const settled = point === "after_result" ||
            point === "after_settlement";
          assertEquals(
            state.reservedCalls,
            point === "before_claim" || settled ? 0 : 1,
          );
          if (point !== "before_claim") {
            assertEquals(
              state.chargedUnits,
              chargeUnits(
                settled ? 110 / 1e6 : reserveCost(
                  plan.runs[0].pricing,
                  prepared.inputs[0].manifest.order[0].model,
                ),
              ),
            );
          }
          await executeExperimentRun(root, plan.runs[0].runId, source, d);
          assertEquals(calls, before);
        } finally {
          await Deno.remove(root, { recursive: true });
        }
      });
    }
  });

  Deno.test("experiment unknown execution, failure, model drift and missing usage stop globally", async (t) => {
    for (
      const failure of [
        "unknown_execution",
        "operational_failure",
        "model_mismatch",
        "usage_missing",
      ] as const
    ) {
      await t.step(failure, async () => {
        const { root, plan, dependencies } = await setup();
        try {
          let calls = 0;
          const state = await executeExperimentRun(
            root,
            plan.runs[0].runId,
            source,
            {
              ...dependencies,
              offlineOutcome: (...args) => {
                calls++;
                const base = dependencies.offlineOutcome(...args);
                if (failure === "model_mismatch") {
                  return { ...base, returnedModel: "gemini-2.5-flash" };
                }
                if (failure === "usage_missing") {
                  return { ...base, usage: null };
                }
                return { ...base, kind: failure };
              },
            },
          );
          assertEquals(calls, 1);
          assertEquals(
            state.stop,
            failure === "unknown_execution" ? "uncertain_execution" : failure,
          );
          assertEquals(
            state.reservedCalls,
            failure === "operational_failure" ? 0 : 1,
          );
          const next = await executeExperimentRun(
            root,
            plan.runs[1].runId,
            source,
            dependencies,
          );
          assertEquals(next.calls, 1);
          assertEquals(next.stop, state.stop);
        } finally {
          await Deno.remove(root, { recursive: true });
        }
      });
    }
  });

  Deno.test("experiment configuration drift remains stopped after the original plan is restored", async (t) => {
    for (const change of ["source", "profile", "price", "window"] as const) {
      await t.step(change, async () => {
        const { root, plan, dependencies } = await setup();
        try {
          await executeExperimentRun(
            root,
            plan.runs[0].runId,
            source,
            dependencies,
          );
          const changed = structuredClone(plan);
          if (change === "profile") {
            changed.runs[1].profileDigest = "9".repeat(64);
          }
          if (change === "price") {
            changed.runs[1].pricing.models[0].outputPerMillion = 2;
          }
          if (change === "window") {
            changed.window.expiresAt = new Date(
              Date.parse(plan.window.expiresAt) + 1000,
            ).toISOString();
          }
          await atomicJson(join(root, "experiment.json"), changed);
          await assertRejects(() =>
            executeExperimentRun(
              root,
              plan.runs[1].runId,
              change === "source"
                ? { ...source, digest: "9".repeat(64) }
                : source,
              dependencies,
            )
          );
          await atomicJson(join(root, "experiment.json"), plan);
          const stopped = await executeExperimentRun(
            root,
            plan.runs[1].runId,
            source,
            dependencies,
          );
          assertEquals(stopped.calls, 4);
          assertEquals(stopped.stop, "configuration_changed");
        } finally {
          await Deno.remove(root, { recursive: true });
        }
      });
    }
  });

  Deno.test("experiment rejects allocation drift, unsupported controls and schedules before claims", async () => {
    const { root, now, plan } = await setup();
    try {
      for (
        const changed of [
          { ...plan, runs: [...plan.runs, ...plan.runs, plan.runs[0]] },
          { ...plan, maxCalls: 33 },
          { ...plan, maxCalls: 7 },
          { ...plan, budgetUsd: 19 },
          { ...plan, cacheControl: "assume_isolated" },
          { ...plan, candidateDecision: "shorter_explanations" },
          {
            ...plan,
            cases: Array.from(
              { length: 9 },
              (_, i) => ({
                caseId: `c${String(i + 1).padStart(4, "0")}`,
                inputDigest: "1".repeat(64),
              }),
            ),
          },
          { ...plan, metrics: { ...plan.metrics, thresholdPercent: 9 } },
        ]
      ) assertThrows(() => parseExperimentPlan(changed));
      const changed = structuredClone(plan);
      changed.runs[0].budgetUsd = 0.01;
      await atomicJson(join(root, "experiment.json"), changed);
      await assertRejects(() => prepareExperiment(root, source, now));
      assertEquals(await exists(join(root, "runs")), false);
      const empty = {
        calls: 0,
        chargedUnits: 0,
        runs: plan.runs.map(() => ({ calls: 0, chargedUnits: 0 })),
      };
      assertEquals(experimentGuard(plan, 0, empty, 1, now), null);
      assertEquals(
        experimentGuard(plan, 0, { ...empty, calls: 8 }, 1, now),
        "call_limit",
      );
      assertEquals(
        experimentGuard(
          plan,
          0,
          { ...empty, chargedUnits: budgetUnits(plan.budgetUsd) },
          1,
          now,
        ),
        "budget_exceeded",
      );
      const perRun = structuredClone(empty);
      perRun.runs[0].chargedUnits = budgetUnits(plan.runs[0].budgetUsd);
      assertEquals(experimentGuard(plan, 0, perRun, 1, now), "budget_exceeded");
      assertEquals(
        experimentGuard(plan, 0, empty, 1, Date.parse(plan.window.expiresAt)),
        "window_expired",
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });

  Deno.test("experiment refuses preexisting runs and detects orphan/tampered journal entries", async (t) => {
    await t.step("preexisting", async () => {
      const { root, plan, dependencies } = await setup();
      try {
        await privateDirectory(join(root, "runs"));
        await privateDirectory(join(root, "runs", "old-run"));
        await assertRejects(() =>
          executeExperimentRun(root, plan.runs[0].runId, source, dependencies)
        );
        assertEquals(
          await exists(join(root, "experiment", "manifest.json")),
          false,
        );
      } finally {
        await Deno.remove(root, { recursive: true });
      }
    });
    for (const kind of ["claim", "settlement"] as const) {
      await t.step(kind, async () => {
        const { root, plan, prepared, dependencies } = await setup();
        try {
          await executeExperimentRun(
            root,
            plan.runs[0].runId,
            source,
            dependencies,
          );
          const key = prepared.inputs[0].manifest.order[0].key;
          if (kind === "claim") {
            await Deno.remove(
              join(
                root,
                "experiment",
                "claims",
                plan.runs[0].runId,
                `${key}.json`,
              ),
            );
          } else {await atomicJson(
              join(
                root,
                "experiment",
                "settlements",
                plan.runs[0].runId,
                `${key}.json`,
              ),
              { chargedUnits: 0 },
            );}
          await assertRejects(() =>
            executeExperimentRun(root, plan.runs[1].runId, source, dependencies)
          );
          const stop = await readJson(
            join(root, "experiment", "stop.json"),
          ) as { reason: string };
          assertEquals(stop.reason, "ledger_mismatch");
        } finally {
          await Deno.remove(root, { recursive: true });
        }
      });
    }
  });

  Deno.test("experiment settles a call finishing after expiry then blocks future calls", async () => {
    const { root, now, plan, dependencies } = await setup();
    try {
      let clock = now + 1, calls = 0;
      const state = await executeExperimentRun(
        root,
        plan.runs[0].runId,
        source,
        {
          ...dependencies,
          now: () => clock,
          offlineOutcome: (...args) => {
            calls++;
            clock = Date.parse(plan.window.expiresAt);
            return dependencies.offlineOutcome(...args);
          },
        },
      );
      assertEquals(calls, 1);
      assertEquals(state.stop, "window_expired");
      assertEquals(state.reservedCalls, 0);
      assertEquals(state.chargedUnits, chargeUnits(110 / 1e6));
      assertEquals(
        (await executeExperimentRun(
          root,
          plan.runs[1].runId,
          source,
          dependencies,
        )).calls,
        1,
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });

  Deno.test("experiment lock prevents a parallel controller from dispatching", async () => {
    const { root, plan, dependencies } = await setup();
    let release!: () => void, entered!: () => void;
    const held = new Promise<void>((r) => release = r),
      started = new Promise<void>((r) => entered = r);
    let pending: Promise<unknown> | undefined;
    try {
      pending = executeExperimentRun(root, plan.runs[0].runId, source, {
        now: dependencies.now,
        prepare: (request, assignment) =>
          createAIExecution(
            {
              provider: "gemini",
              prepare: () => async () => {
                entered();
                await held;
                return dependencies.offlineOutcome(
                  { caseId: assignment.caseId } as Parameters<
                    typeof dependencies.offlineOutcome
                  >[0],
                  assignment,
                );
              },
            },
            request,
            resolveAIClaim(request, fixtureAuthority("gemini_pro", request)),
          ),
      });
      await started;
      await assertRejects(() =>
        executeExperimentRun(root, plan.runs[1].runId, source, dependencies)
      );
      release();
      await pending;
      assertEquals(
        (await executeExperimentRun(
          root,
          plan.runs[1].runId,
          source,
          dependencies,
        )).calls,
        8,
      );
    } finally {
      release();
      await pending?.catch(() => {});
      await Deno.remove(root, { recursive: true });
    }
  });

  Deno.test("experiment reports live-shaped frozen evidence offline without keys and keeps cross-provider costs descriptive", async () => {
    // Every byte is invented. Conversion exercises saved live formats, never dispatch.
    const { root, plan, prepared, dependencies } = await setup();
    try {
      for (const run of plan.runs) {
        await executeExperimentRun(root, run.runId, source, dependencies);
      }
      const before = prepared.inputs[0].corpus;
      assert(before.kind === "exploratory");
      const corpus = parseExploratoryCorpus({
        ...before,
        evidenceOrigin: "real",
        eligibility: {
          recordRef: "synthetic-review",
          reviewerRef: "r0001",
          reviewerKind: "automated",
          retainUntil: "2027-01-01",
        },
        cases: before.cases.map((c) => ({
          ...c,
          curation: {
            kind: "eligibility_reviewed",
            source: "purpose_collected",
            sourceRecordRef: "synthetic-source",
            referenceRecordRef: "synthetic-reference",
            permission: "gemini_evaluation",
            rightsApproved: true,
            personalDataExcluded: true,
            nearDuplicatesReviewed: true,
          },
        })),
      });
      const livePlan = parseExperimentPlan({
        ...plan,
        mode: "live",
        corpusDigest: await fingerprintRunCorpus(corpus),
        runs: plan.runs.map((r) => ({ ...r, readinessDigest: "2".repeat(64) })),
      });
      const digest = await fingerprintJson(livePlan), manifests = [];
      for (const [i, run] of livePlan.runs.entries()) {
        const offline = prepared.inputs[i].manifest;
        const manifest = parseManifest({
          ...offline,
          spec: {
            ...offline.spec,
            mode: "live",
            corpusDigest: livePlan.corpusDigest,
            budgetUsd: run.budgetUsd,
            pricingDigest: run.pricingDigest,
            readinessDigest: run.readinessDigest,
          },
          pricing: run.pricing,
          processor: {
            projectRef: "synthetic-project",
            credentialRef: "synthetic-credential-ref",
          },
          order: offline.order.map((a) => ({
            ...a,
            reservedUsd: reserveCost(run.pricing, a.model),
          })),
        });
        const runDigest = await fingerprintJson(manifest);
        const rd = join(root, "runs", run.runId);
        await atomicJson(join(rd, "manifest.json"), manifest);
        for (const a of manifest.order) {
          const claim = await readJson(
            join(rd, "claims", `${a.key}.json`),
          ) as Record<string, unknown>;
          await atomicJson(join(rd, "claims", `${a.key}.json`), {
            ...claim,
            runDigest,
            reservedUsd: a.reservedUsd,
          });
          const result = parseAttempt(
            await readJson(join(rd, "results", `${a.key}.json`)),
          );
          await atomicJson(join(rd, "results", `${a.key}.json`), {
            ...result,
            runDigest,
            estimatedUpperUsd: estimateCost(run.pricing, a.model, result.usage),
          });
          const globalClaim = await readJson(
            join(root, "experiment", "claims", run.runId, `${a.key}.json`),
          ) as Record<string, unknown>;
          await atomicJson(
            join(root, "experiment", "claims", run.runId, `${a.key}.json`),
            { ...globalClaim, planDigest: digest, runDigest },
          );
          await Deno.remove(
            join(root, "experiment", "settlements", run.runId, `${a.key}.json`),
          );
        }
        manifests.push({ profile: prepared.profiles[i], manifest });
      }
      await atomicJson(join(root, "corpus.json"), corpus);
      await atomicJson(join(root, "experiment.json"), livePlan);
      await atomicJson(join(root, "experiment", "manifest.json"), {
        version: "identification_experiment_v1",
        plan: livePlan,
        planDigest: digest,
        runs: manifests,
      });
      await Deno.remove(join(root, "assets"), { recursive: true });
      const report = await saveExperimentReport(root);
      assertEquals(report.complete, true);
      assertEquals(report.evidenceStatus, "provisional_measurement_only");
      assertEquals(report.productionQualified, false);
      const all = report.comparisons[0].slices.find((s) =>
        s.inputGroup === "all_cases"
      )!;
      assert(
        all.baseline.cost.totalEstimatedUsd !== null &&
          all.candidate.cost.totalEstimatedUsd !== null,
      );
      assertEquals(all.costMeasurementsComparable, false);
      assertEquals(all.observedCostImprovementPercent, null);
      assertEquals(await saveExperimentReport(root), report);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });

  Deno.test("experiment CLI runs a synthetic two-provider plan without credentials", async () => {
    const parent = await Deno.makeTempDir({
      dir: scratch,
      prefix: "experiment-cli-",
    });
    const root = join(parent, "packet");
    try {
      await main(["demo-experiment", root]);
      const state = await readJson(join(root, "experiment", "state.json")) as {
        calls: number;
        stop: null;
        accountingMode: string;
      };
      assertEquals(state.calls, 8);
      assertEquals(state.stop, null);
      assertEquals(state.accountingMode, "synthetic_budget_simulation");
      await main(["experiment-preflight", root]);
      assertEquals(
        (await readJson(join(root, "experiment-preflight.json")) as {
          dispatchAuthorized: boolean;
        }).dispatchAuthorized,
        false,
      );
      const report = await readJson(join(root, "experiment-report.json"));
      await Deno.remove(join(root, "assets"), { recursive: true });
      await main(["experiment-report", root]);
      assertEquals(
        await readJson(join(root, "experiment-report.json")),
        report,
      );
      await main(["report", root, "offline-baseline-1"]);
      await main(["report", root, "offline-baseline-2"]);
    } finally {
      await Deno.remove(parent, { recursive: true });
    }
  });
}
