/** Uses existing durable claims, accounting and scoring; no retries or new validation. */
import { dirname, join } from "node:path";
import type {
  AIProviderOutcome,
  MultimodalAIRequest,
} from "../../functions/_shared/ai/contracts.ts";
import { createAIExecution } from "../../functions/_shared/ai/execution.ts";
import {
  createOpenAIConfidenceEvaluationAdapter,
  createOpenAIPhotoPrimaryEvaluationAdapter,
} from "../../functions/_shared/ai/openai.ts";
import { openAIConfidenceSnapshot } from "../../functions/_shared/ai/openaiPhotoConfidence.ts";
import { openAIPhotoPrimarySnapshot } from "../../functions/_shared/ai/openaiPhotoPrimary.ts";
import { liveCredential } from "./admission.ts";
import { prepareEvidence } from "./assets.ts";
import {
  confidenceAccounting,
  confidenceCost,
  parseConfidenceAccounting,
} from "./confidenceAccounting.ts";
import { parseConfidenceObservation } from "./confidenceScoring.ts";
import { projectDevelopmentDraft } from "./developmentProjection.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  atomicJson,
  claimJson,
  exists,
  privateDirectory,
  readJson,
} from "./files.ts";
import { decisionMetrics, decisionRows } from "./photoDecisionStatistics.ts";
import {
  PRIMARY_SCREEN as P,
  type PrimaryScreenArm,
  type PrimaryScreenAssignment,
  type PrimaryScreenStudy,
  screenRequest,
} from "./photoPrimaryScreenPreparation.ts";
import {
  fields,
  integer,
  member,
  requireCondition as check,
} from "./validation.ts";

const name = (ordinal: number) => String(ordinal).padStart(2, "0");
const claimFor = (study: PrimaryScreenStudy, a: PrimaryScreenAssignment) => ({
  version: "photo_primary_screen_claim_v1",
  manifestDigest: study.digest,
  assignment: a,
});
const cost = (
  accounting: ReturnType<typeof confidenceAccounting>,
  study: PrimaryScreenStudy,
) => {
  const n = confidenceCost(accounting, study.pricing);
  return n === null ? null : Math.ceil(n * P.billingMultiplier);
};
/** Reject durable prose/unknown fields before any report can echo a record. */
function parseDiagnostics(value: unknown) {
  if (value === null) return null;
  const d = fields(value, [
    "version",
    "stage",
    "status",
    "before",
    "after",
    "sanitizerChanged",
    "petAliasChanged",
    "nameChanged",
    "processedMaterialDemoted",
    "declaredResolution",
    "effectiveResolution",
    "beforeMapping",
    "afterMapping",
    "catalogRank",
    "rankAgreement",
  ]);
  check(d.version === "photo_development_diagnostics_v1");
  member(d.stage, ["decode", "normalization", "taxonomy"]);
  member(d.status, ["rejected", "accepted", "rank_conflict"]);
  for (const k of ["before", "after"]) {
    if (k === "after" && d[k] === null) continue;
    const f = fields(d[k], ["present", "annotation"]);
    check(typeof f.present === "boolean" && typeof f.annotation === "boolean");
  }
  for (const k of ["sanitizerChanged", "petAliasChanged", "nameChanged"]) {
    check(d[k] === null || typeof d[k] === "boolean");
  }
  check(typeof d.processedMaterialDemoted === "boolean");
  for (const k of ["declaredResolution", "effectiveResolution"]) {
    member(d[k], [
      null,
      "species",
      "genus",
      "family",
      "unresolved_biological",
      "non_biological",
    ]);
  }
  for (const k of ["beforeMapping", "afterMapping"]) {
    if (d[k] === null) continue;
    const m = fields(d[k], ["status", "match"]);
    member(m.status, ["matched", "unmapped", "ambiguous", "not_applicable"]);
    check(
      m.status === "matched"
        ? ["canonical", "synonym"].includes(m.match as string)
        : m.match === null,
    );
  }
  member(d.catalogRank, [
    null,
    "kingdom",
    "phylum",
    "class",
    "order",
    "family",
    "genus",
    "species",
  ]);
  member(d.rankAgreement, [
    "not_declared",
    "not_applicable",
    "unverified",
    "consistent",
    "conflict",
  ]);
  return d;
}
export async function primaryScreenReport(
  root: string,
  study: PrimaryScreenStudy,
) {
  const directory = await privateDirectory(join(root, "screen-attempts"));
  const allowed = study.manifest.assignments.flatMap(
    (a) => [`${name(a.ordinal)}.claim.json`, `${name(a.ordinal)}.result.json`],
  );
  for await (const e of Deno.readDir(directory)) {
    check(e.isFile && !e.isSymlink && allowed.includes(e.name));
  }
  let attempted = 0, settledNanoUsd = 0, outstandingNanoUsd = 0;
  let stop: string | null = null;
  const records: {
    ordinal: number;
    caseId: string;
    arm: PrimaryScreenArm;
    observation: ReturnType<typeof parseConfidenceObservation>;
    diagnostics: ReturnType<typeof parseDiagnostics>;
    accounting: ReturnType<typeof confidenceAccounting>;
    settledNanoUsd: number | null;
    durationMs: number;
  }[] = [];
  for (const a of study.manifest.assignments) {
    const base = join(directory, name(a.ordinal));
    if (!await exists(base + ".claim.json")) {
      check(!await exists(base + ".result.json"));
      continue;
    }
    check(a.ordinal === attempted + 1 && stop === null);
    const claim = claimFor(study, a);
    check(
      await fingerprintJson(await readJson(base + ".claim.json")) ===
        await fingerprintJson(claim),
    );
    attempted++;
    if (!await exists(base + ".result.json")) {
      outstandingNanoUsd += a.reservedNanoUsd;
      stop = "interrupted_attempt";
      continue;
    }
    const r = fields(await readJson(base + ".result.json"), [
      "version",
      "claimDigest",
      "observation",
      "diagnostics",
      "accounting",
      "settledNanoUsd",
      "durationMs",
    ]);
    check(
      r.version === "photo_primary_screen_result_v1" &&
        r.claimDigest === await fingerprintJson(claim),
    );
    const observation = parseConfidenceObservation(r.observation);
    check(observation.prediction.caseId === a.caseId);
    const diagnostics = parseDiagnostics(r.diagnostics);
    const accounting = parseConfidenceAccounting(r.accounting);
    const settled = cost(accounting, study);
    check(
      settled === r.settledNanoUsd &&
        (settled === null || settled <= a.reservedNanoUsd),
    );
    check(
      typeof r.durationMs === "number" && Number.isFinite(r.durationMs) &&
        r.durationMs >= 0 && r.durationMs <= 600000,
    );
    if (settled === null) {
      outstandingNanoUsd += a.reservedNanoUsd;
      stop = "accounting_incomplete";
    } else settledNanoUsd += settled;
    if (
      ["operational_failure", "unknown_execution"].includes(
        observation.prediction.outcome,
      )
    ) stop ??= "provider_failure";
    // Schema/rank/refusal failures retain their slot and earn no credit; never replace them.
    records.push({
      ordinal: a.ordinal,
      caseId: a.caseId,
      arm: a.arm,
      observation,
      diagnostics,
      accounting,
      settledNanoUsd: settled,
      durationMs: r.durationMs,
    });
  }
  check(settledNanoUsd + outstandingNanoUsd <= P.budgetNanoUsd);
  const next = study.manifest.assignments[attempted];
  if (
    next &&
    settledNanoUsd + outstandingNanoUsd + next.reservedNanoUsd > P.budgetNanoUsd
  ) stop ??= "budget_exhausted";
  const complete = attempted === P.maxCalls && stop === null;
  const rows = (arm: PrimaryScreenArm) =>
    decisionRows(
      study.cases,
      records.filter((r) => r.arm === arm).map((r) => r.observation),
    );
  const released = rows("released"), primary = rows("primary");
  const wins = primary.filter((r, i) => r.success && !released[i].success);
  const losses = primary.filter((r, i) => !r.success && released[i].success);
  const correct = (id: string) =>
    primary.find((r) => r.c.input.caseId === id)?.success === true;
  const unresolvedGains =
    primary.filter((r, i) =>
      r.c.reference.subject === "biological" &&
      r.c.reference.resolution === "unresolved" &&
      r.assessment.appropriateUnresolved &&
      !released[i].assessment.appropriateUnresolved
    ).length;
  const newSubjectErrors =
    primary.filter((r, i) =>
      released[i].assessment.subjectCorrect && !r.assessment.subjectCorrect
    ).length;
  const nonmappingGain = wins.some((r) => {
    const previous = released.find((x) =>
      x.c.input.caseId === r.c.input.caseId
    )!;
    return !previous.assessment.unmapped;
  });
  const speciesLosses =
    losses.filter((r) => r.c.reference.supportedRank === "species").length;
  const screenPassed = complete && P.regressionIds.every(correct) &&
    P.retainedGainIds.every(correct) &&
    unresolvedGains >= P.minimumUnresolvedGains && newSubjectErrors === 0 &&
    speciesLosses === 0 && wins.length - losses.length >= P.minimumNetGain &&
    nonmappingGain;
  const report = {
    version: "photo_primary_screen_report_v1",
    manifestDigest: study.digest,
    purpose: "exposed_development_only",
    protocol: P,
    attempted,
    settledNanoUsd,
    outstandingNanoUsd,
    stop,
    complete,
    arms: Object.fromEntries(
      (["released", "primary"] as const).map(
        (arm) => [
          arm,
          decisionMetrics(
            study.cases,
            records.filter((r) => r.arm === arm).map((r) => r.observation),
          ),
        ],
      ),
    ),
    screen: {
      passed: screenPassed,
      wins: wins.map((r) => r.c.input.caseId),
      losses: losses.map((r) => r.c.input.caseId),
      unresolvedGains,
      newSubjectErrors,
      speciesLosses,
      nonmappingGain,
    },
    records,
    productionActivation: false,
    confidenceQualification: false,
    superiorityEstablished: false,
  };
  await atomicJson(join(root, "screen-report.json"), report);
  return { report, next: stop ? null : next };
}
export async function dispatchPrimaryScreen(
  root: string,
  study: PrimaryScreenStudy,
  expectedArm: PrimaryScreenArm,
  offlineOutcome?: (
    a: PrimaryScreenAssignment,
    request: MultimodalAIRequest,
  ) => Promise<AIProviderOutcome>,
) {
  const live = study.plan.mode === "live";
  check(live ? offlineOutcome === undefined : offlineOutcome !== undefined);
  check(study.plan.mode !== "live" || study.plan.paidServiceApproved === true);
  const { next: a } = await primaryScreenReport(root, study);
  check(a && a.arm === expectedArm);
  if (live) {
    const age = Date.now() - Date.parse(study.pricing.retrievedAt);
    check(
      age >= 0 && age <= 7 * 86400000 &&
        Date.now() < Date.parse(String(study.plan.retainUntil)),
    );
    const directory = await privateDirectory(
      join(dirname(root), ".photo-primary-screen-authorizations"),
    );
    const path = join(
      directory,
      await fingerprintJson(study.plan.authorizationRef) + ".json",
    );
    const receipt = {
      version: P.version,
      rootDigest: study.plan.packetRootDigest,
      manifestDigest: study.digest,
    };
    if (!await exists(path)) await claimJson(path, receipt);
    check(
      await fingerprintJson(await readJson(path)) ===
        await fingerprintJson(receipt),
    );
  }
  const c = study.cases.find((c) => c.input.caseId === a.caseId)!;
  const request = await prepareEvidence(root, c.input);
  const native = screenRequest(request, a.arm);
  check(
    await fingerprintJson(native.parameters) === a.requestDigest &&
      await fingerprintJson(native.snapshot) === a.snapshotDigest,
  );
  const credential = live ? await liveCredential("openai") : "";
  const execution = !live ? null : a.arm === "primary"
    ? createAIExecution(
      createOpenAIPhotoPrimaryEvaluationAdapter(credential),
      request,
      openAIPhotoPrimarySnapshot(request),
    )
    : createAIExecution(
      createOpenAIConfidenceEvaluationAdapter(credential),
      request,
      openAIConfidenceSnapshot(request),
    );
  const claim = claimFor(study, a),
    base = join(root, "screen-attempts", name(a.ordinal));
  await claimJson(base + ".claim.json", claim);
  let outcome: AIProviderOutcome;
  try {
    outcome = execution
      ? await execution.invoke()
      : await offlineOutcome!(a, request);
  } catch {
    outcome = {
      kind: "unknown_execution",
      providerDurationMs: 0,
      providerCompletedAt: Date.now(),
      returnedModel: null,
      usage: null,
      finishReason: null,
      responseCharacters: 0,
    };
  }
  const projection =
    outcome.kind === "draft" && outcome.returnedModel === "gpt-6-sol" &&
      outcome.serviceTier === "default" &&
      outcome.mediaSafety?.disposition === "allowed"
      ? projectDevelopmentDraft(
        a.caseId,
        a.arm === "primary" ? "explicit_primary" : "legacy",
        outcome.draft,
        study.taxonomy,
      )
      : {
        observation: parseConfidenceObservation({
          prediction: {
            caseId: a.caseId,
            outcome: outcome.kind === "draft" ? "invalid_output" : outcome.kind,
          },
          mapping: null,
        }),
        diagnostics: null,
      };
  const accounting = confidenceAccounting(outcome),
    settledNanoUsd = cost(accounting, study);
  if (settledNanoUsd !== null) integer(settledNanoUsd, 0, a.reservedNanoUsd);
  await claimJson(base + ".result.json", {
    version: "photo_primary_screen_result_v1",
    claimDigest: await fingerprintJson(claim),
    ...projection,
    accounting,
    settledNanoUsd,
    durationMs: outcome.providerDurationMs,
  });
  return await primaryScreenReport(root, study);
}
