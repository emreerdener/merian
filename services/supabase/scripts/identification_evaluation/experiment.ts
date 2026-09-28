import { assertPrivateReviewReady } from "./explanationView.ts";
import {
  assessmentMatches,
  type ExplanationAssessment,
  parseAssessment,
  type Ratings,
  ratingsPass,
  unavailableRatings,
} from "./explanationContracts.ts";
import {
  assessmentBinding,
  explanationDisplay,
  reviewExplanation,
  reviewInputs,
} from "./explanationReview.ts";
import type { ReviewDisplay } from "./explanationView.ts";
import type {
  AIProviderOutcome,
  MultimodalAIRequest,
} from "../../functions/_shared/ai/contracts.ts";
import type { EvaluationInput } from "./contracts.ts";
/** One locked experiment across provider-scoped runs. Never loads another provider's key. */
import { join } from "node:path";
import {
  assertOfflinePermissions,
  validateSelectionFacts,
} from "./admission.ts";
import { prepareEvidence } from "./assets.ts";
import { fingerprintJson } from "./evidence.ts";
import { parseRunCorpus } from "./exploratory.ts";
import {
  budgetUnits,
  chargeUnits,
  EXPERIMENT_STOPS,
  experimentGuard,
  experimentSpecVersion,
  type ExperimentStop,
  hasAssistantReview,
  NULL_FIELDS_PLAN_VERSION,
  parseExperimentPlan,
} from "./experimentContracts.ts";
import {
  atomicJson,
  claimJson,
  exists,
  privateDirectory,
  readJson,
  withRunLock,
} from "./files.ts";
import { estimateCost, reserveCost } from "./profiles.ts";
import {
  executionProfile,
  reusableAssignmentFor,
  reusableProfile,
} from "./reusableProfiles.ts";
import {
  type Assignment,
  type AttemptRecord,
  type EvaluationPricing,
  parseEvaluationReadiness,
  parseManifest,
  parseRunSpec,
  parseTaxonomy,
  type RunManifest,
  type SourceIdentity,
} from "./runContracts.ts";
import {
  assembleRun,
  type EvaluationInputs,
  executeRun,
  readRecords,
  type RunnerDependencies,
  stopAfter,
} from "./runner.ts";
import { MEASUREMENT_SCORER } from "./taxonomy.ts";
import { validateReportInputs } from "./reports.ts";
import {
  fields,
  member,
  requireCondition as check,
  token,
} from "./validation.ts";

export interface ExperimentRunControl {
  readonly pricing: EvaluationPricing;
  readonly readinessPath: string;
  beforeClaim(assignment: Assignment): Promise<string | null>;
  afterResult(
    a: Assignment,
    record: AttemptRecord,
    outcome: AIProviderOutcome | null,
    request: MultimodalAIRequest,
    input: EvaluationInput,
  ): Promise<string | null>;
}
// No public constructor: only the verified controller holding the experiment lock
// can register a live capability. JSON, booleans and RunnerDependencies cannot.
const active = new WeakMap<
  ExperimentRunControl,
  { root: string; digest: string }
>();
export async function activeExperimentControl(
  control: ExperimentRunControl,
  root: string,
  manifest: RunManifest,
) {
  const bound = active.get(control);
  return !!bound && bound.root === root &&
    bound.digest === await fingerprintJson(manifest);
}

export async function prepareExperiment(
  root: string,
  source: SourceIdentity,
  now = Date.now(),
) {
  const plan = parseExperimentPlan(
    await readJson(join(root, "experiment.json")),
  );
  check(await fingerprintJson(plan.source) === await fingerprintJson(source));
  const corpus = parseRunCorpus(await readJson(join(root, "corpus.json")));
  const taxonomy = parseTaxonomy(
    await readJson(join(root, "taxonomy.json"), 32 * 1024 * 1024),
  );
  check(
    corpus.kind === "exploratory" &&
      taxonomy.version === "evaluation_taxonomy_v2" &&
      corpus.preparationVersion === plan.preparationVersion,
  );
  check(
    corpus.cases.every((c) =>
      c.input.inputGroup === "photos" || c.input.inputGroup === "description"
    ),
  );
  const reviewFacts = plan.review ? await reviewInputs(root, plan) : null;
  if (plan.version === NULL_FIELDS_PLAN_VERSION) {
    check(corpus.cases.every((c) => c.input.inputGroup === "photos"));
  } else if (plan.review && plan.mode === "live") {
    check(
      corpus.cases.filter((c) => c.input.inputGroup === "photos").length ===
          6 &&
        corpus.cases.filter((c) => c.input.inputGroup === "description")
            .length === 2,
    );
  }
  const inputs: EvaluationInputs[] = [], profiles = [];
  for (const run of plan.runs) {
    const profile = await reusableProfile(run.profileId);
    check(
      profile.digest === run.profileDigest &&
        await fingerprintJson(run.pricing) === run.pricingDigest,
    );
    const age = now - Date.parse(run.pricing.retrievedAt);
    check(age >= 0 && age <= 7 * 86400000);
    let processor: RunManifest["processor"] = null;
    if (plan.mode === "live") {
      const readiness = parseEvaluationReadiness(
        await readJson(join(root, "approvals", `${run.runId}.json`)),
      );
      check(await fingerprintJson(readiness) === run.readinessDigest);
      processor = {
        projectRef: readiness.projectRef,
        credentialRef: readiness.credentialRef,
      };
    }
    const spec = parseRunSpec({
      version: experimentSpecVersion(plan),
      runId: run.runId,
      mode: plan.mode,
      corpusDigest: plan.corpusDigest,
      taxonomyDigest: plan.taxonomyDigest,
      split: "development",
      stage: "exploratory",
      profiles: [executionProfile(run.profileId)],
      caseIds: plan.cases.map((c) => c.caseId),
      repeats: 1,
      orderSeed: plan.orderSeed,
      maxCalls: run.maxCalls,
      budgetUsd: plan.mode === "live" ? run.budgetUsd : 0,
      pricingDigest: plan.mode === "live" ? run.pricingDigest : null,
      readinessDigest: run.readinessDigest,
    });
    await validateSelectionFacts(corpus, spec, taxonomy);
    const input = await assembleRun(
      root,
      corpus,
      taxonomy,
      spec,
      source,
      plan.mode === "live" ? run.pricing : null,
      processor,
      Date.parse(plan.window.startsAt),
    );
    check(input.manifest.scorerVersion === MEASUREMENT_SCORER);
    for (const assignment of input.manifest.order) {
      const item = corpus.cases.find((c) =>
        c.input.caseId === assignment.caseId
      )!.input;
      check(
        assignment.inputDigest ===
          plan.cases.find((c) => c.caseId === assignment.caseId)!.inputDigest,
      );
      check(
        await fingerprintJson(assignment) ===
          await fingerprintJson(
            await reusableAssignmentFor(
              item,
              await prepareEvidence(root, item),
              run.profileId,
              1,
              input.manifest.pricing,
            ),
          ),
      );
    }
    const fullReservation = input.manifest.order.reduce(
      (n, a) => n + chargeUnits(reserveCost(run.pricing, a.model)),
      0,
    );
    check(fullReservation <= budgetUnits(run.budgetUsd));
    inputs.push(input);
    profiles.push(profile);
  }
  return {
    plan,
    digest: await fingerprintJson(plan),
    inputs,
    profiles,
    reviewFacts,
  };
}
type PreparedExperiment = Awaited<ReturnType<typeof prepareExperiment>>;

/** Regeneration uses the frozen manifests and bounded records, never media or a key. */
export async function experimentReportSnapshot(root: string) {
  await assertOfflinePermissions();
  const directory = await privateDirectory(join(root, "experiment"));
  return await withRunLock(directory, async () => {
    const frozen = fields(await readJson(join(directory, "manifest.json")), [
      "version",
      "plan",
      "planDigest",
      "runs",
    ]);
    check(frozen.version === "identification_experiment_v1");
    const plan = parseExperimentPlan(frozen.plan),
      digest = await fingerprintJson(plan);
    check(
      frozen.planDigest === digest && Array.isArray(frozen.runs) &&
        frozen.runs.length === plan.runs.length,
    );
    check(
      await fingerprintJson(
        parseExperimentPlan(await readJson(join(root, "experiment.json"))),
      ) === digest,
    );
    const corpus = parseRunCorpus(await readJson(join(root, "corpus.json")));
    const taxonomy = parseTaxonomy(
      await readJson(join(root, "taxonomy.json"), 32 * 1024 * 1024),
    );
    const inputs: EvaluationInputs[] = [],
      profiles: PreparedExperiment["profiles"] = [];
    for (const [i, run] of plan.runs.entries()) {
      const saved = fields(frozen.runs[i], ["profile", "manifest"]);
      const profile = fields(saved.profile, ["definition", "digest"]);
      check(
        profile.digest === run.profileDigest &&
          await fingerprintJson(profile.definition) === run.profileDigest,
      );
      // Descriptors are never emitted as arbitrary saved objects in a report.
      const manifest = parseManifest(saved.manifest), spec = manifest.spec;
      check(
        spec.version === experimentSpecVersion(plan) &&
          spec.runId === run.runId && spec.mode === plan.mode &&
          spec.stage === "exploratory" && spec.repeats === 1 &&
          spec.corpusDigest === plan.corpusDigest &&
          spec.taxonomyDigest === plan.taxonomyDigest &&
          spec.orderSeed === plan.orderSeed &&
          spec.profiles.length === 1 &&
          spec.profiles[0] === executionProfile(run.profileId) &&
          spec.maxCalls === run.maxCalls &&
          spec.budgetUsd === (plan.mode === "live" ? run.budgetUsd : 0) &&
          spec.readinessDigest === run.readinessDigest &&
          spec.pricingDigest ===
            (plan.mode === "live" ? run.pricingDigest : null),
      );
      check(
        await fingerprintJson(manifest.source) ===
            await fingerprintJson(plan.source) &&
          manifest.scorerVersion === MEASUREMENT_SCORER &&
          manifest.preparationVersion === plan.preparationVersion &&
          manifest.order.length === plan.cases.length,
      );
      check(
        await fingerprintJson(run.pricing) === run.pricingDigest &&
          (plan.mode !== "live" ||
            await fingerprintJson(manifest.pricing) === run.pricingDigest),
      );
      for (const a of manifest.order) {
        check(
          a.inputDigest ===
            plan.cases.find((c) => c.caseId === a.caseId)?.inputDigest,
        );
      }
      const records = await readRecords(
        join(root, "runs", run.runId),
        manifest,
      );
      await validateReportInputs(corpus, manifest, records, taxonomy);
      inputs.push({ corpus, taxonomy, manifest });
    }
    const prepared = { plan, digest, inputs, profiles, reviewFacts: null };
    let accounting: Accounting;
    try {
      accounting = await reconcile(root, directory, prepared);
    } catch (error) {
      await persistStop(directory, digest, "ledger_mismatch");
      throw error;
    }
    const runs = await Promise.all(
      inputs.map(async (input) => ({
        ...input,
        records: await readRecords(
          join(root, "runs", input.manifest.spec.runId),
          input.manifest,
        ),
      })),
    );
    const assessments: { record: ExplanationAssessment; digest: string }[] = [];
    if (plan.review) {
      for (const run of plan.runs) {
        for (
          const a of inputs.find((i) => i.manifest.spec.runId === run.runId)!
            .manifest.order
        ) {
          const path = join(
            directory,
            "assessments",
            run.runId,
            `${a.key}.json`,
          );
          if (await exists(path)) {
            const record = parseAssessment(await readJson(path, 16384));
            assessments.push({ record, digest: await fingerprintJson(record) });
          }
        }
      }
    }
    return { plan, digest, accounting, runs, assessments };
  });
}

interface Accounting {
  calls: number;
  chargedUnits: number;
  reservedCalls: number;
  completedRunIds: string[];
  runs: {
    runId: string;
    calls: number;
    chargedUnits: number;
    reservedCalls: number;
  }[];
  stop: ExperimentStop | null;
}
async function onlyEntries(directory: string, allowed: readonly string[]) {
  for await (const entry of Deno.readDir(directory)) {
    // Atomic write debris never grants execution and remains unexamined.
    check(
      !entry.isSymlink &&
        (allowed.includes(entry.name) || entry.name.endsWith(".tmp")),
    );
  }
}
async function persistStop(
  directory: string,
  digest: string,
  reason: ExperimentStop,
): Promise<ExperimentStop> {
  const path = join(directory, "stop.json");
  if (await exists(path)) {
    const v = fields(await readJson(path, 4096), [
      "version",
      "planDigest",
      "reason",
    ]);
    check(
      v.version === "identification_experiment_stop_v1" &&
        v.planDigest === digest,
    );
    member(v.reason, EXPERIMENT_STOPS);
    return v.reason;
  }
  await claimJson(path, {
    version: "identification_experiment_stop_v1",
    planDigest: digest,
    reason,
  });
  return reason;
}

async function reconcile(
  root: string,
  directory: string,
  prepared: PreparedExperiment,
  pending?: { runId: string; key: string },
): Promise<Accounting> {
  const { plan, digest, inputs } = prepared;
  const accounting: Accounting = {
    calls: 0,
    chargedUnits: 0,
    reservedCalls: 0,
    completedRunIds: [],
    runs: [],
    stop: null,
  };
  if (await exists(join(directory, "stop.json"))) {
    accounting.stop = await persistStop(directory, digest, "ledger_mismatch");
  }
  await onlyEntries(join(root, "runs"), plan.runs.map((r) => r.runId));
  for (
    const kind of [
      "claims",
      "settlements",
      ...(plan.review ? ["assessments"] : []),
    ]
  ) {
    await onlyEntries(
      join(directory, kind),
      plan.runs.map((r) => r.runId),
    );
  }
  let incomplete = false;
  for (const [i, run] of plan.runs.entries()) {
    const manifest = inputs[i].manifest,
      runDigest = await fingerprintJson(manifest);
    const runDirectory = join(root, "runs", run.runId);
    check(
      await fingerprintJson(
        parseManifest(await readJson(join(runDirectory, "manifest.json"))),
      ) === runDigest,
    );
    const keys = manifest.order.map((a) => `${a.key}.json`);
    for (const kind of ["claims", "results"]) {
      await onlyEntries(join(runDirectory, kind), keys);
    }
    for (
      const kind of [
        "claims",
        "settlements",
        ...(plan.review ? ["assessments"] : []),
      ]
    ) {
      await onlyEntries(join(directory, kind, run.runId), keys);
    }
    const records = await readRecords(runDirectory, manifest);
    const summary = {
      runId: run.runId,
      calls: 0,
      chargedUnits: 0,
      reservedCalls: 0,
    };
    let completed = true, gap = false;
    for (const [j, a] of manifest.order.entries()) {
      const claimPath = join(directory, "claims", run.runId, `${a.key}.json`);
      const settlementPath = join(
        directory,
        "settlements",
        run.runId,
        `${a.key}.json`,
      );
      const global = await exists(claimPath),
        local = await exists(join(runDirectory, "claims", `${a.key}.json`));
      const hasResult = await exists(
        join(runDirectory, "results", `${a.key}.json`),
      );
      if (!global) {
        check(!local && !hasResult && !await exists(settlementPath));
        if (plan.review) {
          check(
            !await exists(
              join(directory, "assessments", run.runId, `${a.key}.json`),
            ),
          );
        }
        gap = true;
        completed = false;
        continue;
      }
      check(!gap && !incomplete);
      const reservationUsd = reserveCost(run.pricing, a.model);
      const expectedClaim = {
        version: "identification_experiment_claim_v1",
        planDigest: digest,
        runId: run.runId,
        runDigest,
        key: a.key,
        requestDigest: a.requestDigest,
        profileId: run.profileId,
        profileDigest: run.profileDigest,
        reservationUsd,
      };
      check(
        await fingerprintJson(await readJson(claimPath, 8192)) ===
          await fingerprintJson(expectedClaim),
      );
      summary.calls++;
      const record = records[j];
      const known = local && hasResult &&
          record.prediction.outcome !== "unknown_execution" &&
          record.reason !== "model_mismatch" && record.returnedModel === a.model
        ? estimateCost(run.pricing, a.model, record.usage)
        : null;
      const units = known === null
        ? chargeUnits(reservationUsd)
        : chargeUnits(known);
      summary.chargedUnits += units;
      if (known === null) summary.reservedCalls++;
      const failure: ExperimentStop | null = !local || !hasResult ||
          record.prediction.outcome === "unknown_execution"
        ? "uncertain_execution"
        : (record.reason === "model_mismatch" ||
            (record.returnedModel !== null && record.returnedModel !== a.model))
        ? "model_mismatch"
        : record.prediction.outcome === "operational_failure"
        ? "operational_failure"
        : known === null
        ? "usage_missing"
        : null;
      if (failure) {
        accounting.stop ??= failure;
        completed = false;
      }
      if (local && hasResult) {
        const settlement = {
          version: "identification_experiment_settlement_v1",
          planDigest: digest,
          runId: run.runId,
          key: a.key,
          resultDigest: await fingerprintJson(record),
          state: known === null ? "reservation_retained" : "settled",
          chargedUnits: units,
        };
        if (await exists(settlementPath)) {
          check(
            await fingerprintJson(await readJson(settlementPath, 8192)) ===
              await fingerprintJson(settlement),
          );
        } else await claimJson(settlementPath, settlement);
      } else check(!await exists(settlementPath));
      if (plan.review && local && hasResult) {
        if (
          plan.cacheControl === "explicit_no_breakpoints_v1" &&
          (record.usage?.cachedTokens !== 0 ||
            record.usage?.cacheWriteTokens !== 0)
        ) accounting.stop ??= "cache_control_failed";
        const path = join(directory, "assessments", run.runId, `${a.key}.json`);
        if (await exists(path)) {
          const binding = await assessmentBinding(
            plan,
            i,
            runDigest,
            a,
            record,
            plan.review.cards.find((c) => c.caseId === a.caseId)!.digest,
          );
          const assessment = await assessmentMatches(
            await readJson(path, 16384),
            binding,
            plan.mode === "live",
            hasAssistantReview(plan),
          );
          if (!ratingsPass(assessment.ratings)) {
            completed = false;
            accounting.stop ??= "explanation_quality_failed";
          }
        } else {
          completed = false;
          if (pending?.runId !== run.runId || pending.key !== a.key) {
            accounting.stop ??= "explanation_review_missing";
          }
        }
      }
    }
    if (summary.calls > run.maxCalls) accounting.stop ??= "call_limit";
    if (summary.chargedUnits > budgetUnits(run.budgetUsd)) {
      accounting.stop ??= "budget_exceeded";
    }
    accounting.runs.push(summary);
    accounting.calls += summary.calls;
    accounting.chargedUnits += summary.chargedUnits;
    accounting.reservedCalls += summary.reservedCalls;
    if (completed) accounting.completedRunIds.push(run.runId);
    else incomplete = true;
  }
  if (accounting.calls > plan.maxCalls) accounting.stop ??= "call_limit";
  if (accounting.chargedUnits > budgetUnits(plan.budgetUsd)) {
    accounting.stop ??= "budget_exceeded";
  }
  if (accounting.stop) {
    accounting.stop = await persistStop(directory, digest, accounting.stop);
  }
  await atomicJson(join(directory, "state.json"), {
    version: "identification_experiment_state_v1",
    planDigest: digest,
    accountingMode: plan.mode === "live"
      ? "conservative_usage"
      : "synthetic_budget_simulation",
    ...accounting,
  });
  return accounting;
}

/** Dependencies are synthetic-only. No live execution accepts an injected clock or adapter. */
export interface ExperimentDependencies extends RunnerDependencies {
  review?: (display: ReviewDisplay | null) => Promise<Ratings | null>;
  now?: () => number;
  experimentCheckpoint?: (
    point: "after_reservation" | "after_settlement",
  ) => void;
}
export async function executeExperimentRun(
  root: string,
  runId: string,
  source: SourceIdentity,
  dependencies: ExperimentDependencies = {},
) {
  token(runId);
  const plan = parseExperimentPlan(
    await readJson(join(root, "experiment.json")),
  );
  if (plan.mode === "live") {
    check(Object.keys(dependencies).length === 0);
    if (plan.review) await assertPrivateReviewReady();
  } else await assertOfflinePermissions();
  const directory = await privateDirectory(join(root, "experiment"));
  // Lock order is always experiment -> run, including reconciliation and settlement.
  return await withRunLock(directory, async () => {
    const now = dependencies.now ?? Date.now;
    const manifestPath = join(directory, "manifest.json");
    let prepared: PreparedExperiment;
    try {
      prepared = await prepareExperiment(root, source, now());
    } catch (error) {
      if (await exists(manifestPath)) {
        const frozen = await readJson(manifestPath) as { plan: unknown };
        await persistStop(
          directory,
          await fingerprintJson(parseExperimentPlan(frozen.plan)),
          "configuration_changed",
        );
      }
      throw error;
    }
    const runIndex = prepared.plan.runs.findIndex((r) => r.runId === runId);
    check(runIndex >= 0);
    const run = prepared.plan.runs[runIndex], input = prepared.inputs[runIndex];
    const frozen = {
      version: "identification_experiment_v1",
      plan: prepared.plan,
      planDigest: prepared.digest,
      runs: prepared.inputs.map((i, index) => ({
        profile: prepared.profiles[index],
        manifest: i.manifest,
      })),
    };
    if (await exists(manifestPath)) {
      if (
        await fingerprintJson(await readJson(manifestPath)) !==
          await fingerprintJson(frozen)
      ) {
        const prior = fields(await readJson(manifestPath), [
          "version",
          "plan",
          "planDigest",
          "runs",
        ]);
        const originalDigest = await fingerprintJson(
          parseExperimentPlan(prior.plan),
        );
        check(prior.planDigest === originalDigest);
        await persistStop(directory, originalDigest, "configuration_changed");
        throw new Error("evaluation_experiment_changed");
      }
    } else {
      if (await exists(join(root, "runs"))) {
        await onlyEntries(join(root, "runs"), []);
      }
      await claimJson(manifestPath, frozen);
    }
    await privateDirectory(join(root, "runs"));
    for (
      const kind of [
        "claims",
        "settlements",
        ...(plan.review ? ["assessments"] : []),
      ]
    ) {
      await privateDirectory(join(directory, kind));
    }
    for (const [i, planned] of prepared.plan.runs.entries()) {
      const rd = await privateDirectory(join(root, "runs", planned.runId));
      for (const kind of ["claims", "results"]) {
        await privateDirectory(join(rd, kind));
      }
      for (
        const kind of [
          "claims",
          "settlements",
          ...(plan.review ? ["assessments"] : []),
        ]
      ) {
        await privateDirectory(join(directory, kind, planned.runId));
      }
      if (!await exists(join(rd, "manifest.json"))) {
        await claimJson(join(rd, "manifest.json"), prepared.inputs[i].manifest);
      }
    }
    const update = async (pending?: { runId: string; key: string }) => {
      try {
        return await reconcile(root, directory, prepared, pending);
      } catch (error) {
        await persistStop(directory, prepared.digest, "ledger_mismatch");
        throw error;
      }
    };
    let accounting = await update();
    if (accounting.stop || accounting.completedRunIds.includes(runId)) {
      return accounting;
    }
    check(accounting.completedRunIds.length === runIndex);
    const control: ExperimentRunControl = {
      pricing: run.pricing,
      readinessPath: join(root, "approvals", `${runId}.json`),
      beforeClaim: async (a) => {
        accounting = await update();
        if (accounting.stop) return accounting.stop;
        const reservationUsd = reserveCost(run.pricing, a.model);
        const reason = experimentGuard(
          prepared.plan,
          runIndex,
          accounting,
          reservationUsd,
          now(),
        );
        if (reason) {
          return await persistStop(directory, prepared.digest, reason);
        }
        await claimJson(join(directory, "claims", runId, `${a.key}.json`), {
          version: "identification_experiment_claim_v1",
          planDigest: prepared.digest,
          runId,
          runDigest: await fingerprintJson(input.manifest),
          key: a.key,
          requestDigest: a.requestDigest,
          profileId: run.profileId,
          profileDigest: run.profileDigest,
          reservationUsd,
        });
        dependencies.experimentCheckpoint?.("after_reservation");
        return null;
      },
      afterResult: async (a, record, outcome, request, observation) => {
        accounting = await update(
          prepared.plan.review ? { runId, key: a.key } : undefined,
        );
        dependencies.experimentCheckpoint?.("after_settlement");
        if (
          !accounting.stop &&
          now() >= Date.parse(prepared.plan.window.expiresAt)
        ) {
          accounting.stop = await persistStop(
            directory,
            prepared.digest,
            "window_expired",
          );
        }
        if (prepared.plan.review && !accounting.stop) {
          const card = prepared.reviewFacts!.cards.find((c) =>
            c.caseId === a.caseId
          )!;
          const binding = await assessmentBinding(
            prepared.plan,
            runIndex,
            await fingerprintJson(input.manifest),
            a,
            record,
            await fingerprintJson(card),
          );
          let ratings: Ratings | null = null;
          try {
            const display =
              outcome && record.prediction.outcome === "normalized"
                ? explanationDisplay(outcome, observation, a, request, card)
                : null;
            ratings = prepared.plan.mode === "live"
              ? await reviewExplanation(
                display,
                prepared.plan.review.timeoutMs,
                hasAssistantReview(prepared.plan),
              )
              : await dependencies.review?.(display) ?? null;
          } catch {
            /* Failed review is bounded and never changes provider accounting. */
          }
          const assessment = parseAssessment({
            version: hasAssistantReview(prepared.plan)
              ? "explanation_assessment_v2"
              : "explanation_assessment_v1",
            binding,
            method: prepared.plan.mode === "live"
              ? hasAssistantReview(prepared.plan)
                ? "assistant_local_v1"
                : "owner_local_v1"
              : "synthetic_fixture_v1",
            ratings: ratings ?? unavailableRatings(),
          });
          await claimJson(
            join(directory, "assessments", runId, `${a.key}.json`),
            assessment,
          );
          accounting = await update();
          if (now() >= Date.parse(prepared.plan.window.expiresAt)) {
            accounting.stop = await persistStop(
              directory,
              prepared.digest,
              "window_expired",
            );
          }
        }
        return accounting.stop;
      },
    };
    active.set(control, {
      root,
      digest: await fingerprintJson(input.manifest),
    });
    try {
      const {
        now: _now,
        experimentCheckpoint: _checkpoint,
        review: _review,
        ...runnerDependencies
      } = dependencies;
      const result = await executeRun(root, input, runnerDependencies, control);
      if (result.stopReason) {
        const reason = result.records.some((r) => stopAfter(r, true))
          ? "run_stopped"
          : "budget_exceeded";
        await persistStop(directory, prepared.digest, reason);
      }
    } catch (error) {
      // Reconcile a durable result before preserving the global stop. Never replay.
      await update();
      await persistStop(directory, prepared.digest, "execution_interrupted");
      throw error;
    } finally {
      active.delete(control);
    }
    return await update();
  });
}
