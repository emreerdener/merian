import { dirname, join } from "node:path";
import type { AIProviderOutcome } from "../../functions/_shared/ai/contracts.ts";
import { createAIExecution } from "../../functions/_shared/ai/execution.ts";
import {
  createOpenAIConfidenceEvaluationAdapter,
  createOpenAIPhotoEvidenceEvaluationAdapter,
} from "../../functions/_shared/ai/openai.ts";
import { openAIConfidenceSnapshot } from "../../functions/_shared/ai/openaiPhotoConfidence.ts";
import { openAIPhotoEvidenceSnapshot } from "../../functions/_shared/ai/openaiPhotoEvidence.ts";
import { normalizeIdentification } from "../../functions/_shared/identify/normalizeIdentification.ts";
import { liveCredential } from "./admission.ts";
import { prepareEvidence } from "./assets.ts";
import {
  confidenceCost,
  parseConfidenceAccounting,
} from "./confidenceAccounting.ts";
import { projectConfidenceOutcome } from "./confidenceProjection.ts";
import {
  type ConfidenceObservation,
  parseConfidenceObservation,
} from "./confidenceScoring.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  atomicJson,
  claimJson,
  exists,
  privateDirectory,
  readJson,
} from "./files.ts";
import { normalizeEvaluationDraft } from "./normalization.ts";
import { estimateCost } from "./profiles.ts";
import { projectOutcome } from "./projection.ts";
import { validateRecord } from "./runner.ts";
import { hash } from "./runContracts.ts";
import { normalizedTaxonomyName } from "./taxonomy.ts";
import { fields, integer, requireCondition as check } from "./validation.ts";
import {
  type DecisionArm,
  type PhotoDecisionAssignment,
  type PhotoDecisionStudy,
} from "./photoDecisionPreparation.ts";
import {
  decisionMetrics,
  decisionRows,
  pairedDecision,
  PHOTO_DECISION_PROTOCOL as P,
  selectEvidenceCandidate,
} from "./photoDecisionStatistics.ts";

const claimFor = (study: PhotoDecisionStudy, a: PhotoDecisionAssignment) => ({
  version: "photo_decision_claim_v1",
  manifestDigest: study.digest,
  assignment: a,
});

export async function decisionSelection(
  root: string,
  study: PhotoDecisionStudy,
) {
  const path = join(root, "validation-freeze.json");
  if (!await exists(path)) return null;
  const v = fields(await readJson(path), [
    "version",
    "manifestDigest",
    "developmentResultsDigest",
    "selection",
    "arms",
    "assignmentsDigest",
  ]);
  check(
    v.version === "photo_decision_validation_freeze_v1" &&
      v.manifestDigest === study.digest,
  );
  hash(v.developmentResultsDigest);
  hash(v.assignmentsDigest);
  check(typeof (v.selection as { selected?: unknown })?.selected === "boolean");
  const selected = (v.selection as { selected: boolean }).selected;
  check(
    await fingerprintJson(v.arms) ===
      await fingerprintJson(
        selected ? ["released", "gemini", "evidence"] : ["released", "gemini"],
      ),
  );
  check(
    v.assignmentsDigest ===
      await fingerprintJson(
        study.manifest.assignments.filter((a) =>
          a.phase === "validation" && (selected || a.arm !== "evidence")
        ),
      ),
  );
  return {
    ...v,
    selected,
    developmentResultsDigest: v.developmentResultsDigest,
    selection: v.selection,
  };
}

export async function readPhotoDecision(
  root: string,
  study: PhotoDecisionStudy,
) {
  const directory = await privateDirectory(join(root, "decision-attempts"));
  const selection = await decisionSelection(root, study);
  const assignments = study.manifest.assignments.filter((a) =>
    a.phase === "development" ||
    selection && (selection.selected || a.arm !== "evidence")
  );
  const allowed = new Set(
    assignments.flatMap((a) =>
      ["claim", "result"].map((s) => `${a.key}.${s}.json`)
    ),
  );
  for await (const e of Deno.readDir(directory)) {
    check(e.isFile && !e.isSymlink && allowed.has(e.name));
  }
  let attempted = 0, settledNanoUsd = 0, outstandingNanoUsd = 0;
  let stop: string | null = null, gap = false;
  const records: {
    assignment: PhotoDecisionAssignment;
    observation: ConfidenceObservation;
    settledNanoUsd: number | null;
    providerDurationMs: number;
    primaryNameDigest: string | null;
    nameForm: string | null;
    resultDigest: string;
  }[] = [];
  for (const a of assignments) {
    const base = join(directory, a.key);
    if (!await exists(base + ".claim.json")) {
      check(!await exists(base + ".result.json"));
      gap = true;
      continue;
    }
    check(!gap && stop === null);
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
    const result = fields(await readJson(base + ".result.json"), [
      "version",
      "claimDigest",
      "observation",
      "accounting",
      "geminiRecord",
      "settledNanoUsd",
      "providerDurationMs",
      "primaryNameDigest",
      "nameForm",
    ]);
    check(
      result.version === "photo_decision_result_v1" &&
        result.claimDigest === await fingerprintJson(claim),
    );
    const observation = parseConfidenceObservation(result.observation);
    check(observation.prediction.caseId === a.caseId);
    let cost: number | null;
    if (a.arm === "gemini") {
      check(result.accounting === null && a.gemini !== null);
      const record = validateRecord(
        result.geminiRecord,
        a.gemini,
        study.digest,
        study.geminiPricing,
        true,
      );
      check(
        await fingerprintJson({
          prediction: record.prediction,
          mapping: record.mapping,
        }) === await fingerprintJson(observation),
      );
      const estimate = estimateCost(
        study.geminiPricing,
        a.gemini.model,
        record.usage,
      );
      cost = estimate !== null && record.returnedModel === a.gemini.model &&
          !["unknown_execution", "operational_failure"].includes(
            record.prediction.outcome,
          )
        ? Math.ceil(estimate * 1e9)
        : null;
    } else {
      check(result.geminiRecord === null);
      const accounted = confidenceCost(
        parseConfidenceAccounting(result.accounting),
        study.openaiPricing,
      );
      cost = accounted === null ? null : Math.ceil(accounted * 1.1);
    }
    check(
      cost === result.settledNanoUsd &&
        (cost === null || cost <= a.reservedNanoUsd),
    );
    if (cost === null) {
      outstandingNanoUsd += a.reservedNanoUsd;
      stop = "accounting_incomplete";
    } else settledNanoUsd += cost;
    check(
      typeof result.providerDurationMs === "number" &&
        Number.isFinite(result.providerDurationMs) &&
        result.providerDurationMs >= 0 && result.providerDurationMs <= 300000,
    );
    const named = observation.prediction.outcome === "normalized" &&
      observation.prediction.subject === "biological" &&
      observation.prediction.resolution === "named";
    check(named === (result.primaryNameDigest !== null));
    if (result.primaryNameDigest !== null) hash(result.primaryNameDigest);
    check(
      named
        ? ["plain", "qualifier_or_annotation"].includes(String(result.nameForm))
        : result.nameForm === null,
    );
    records.push({
      assignment: a,
      observation,
      settledNanoUsd: cost,
      providerDurationMs: result.providerDurationMs,
      primaryNameDigest: result.primaryNameDigest as string | null,
      nameForm: result.nameForm as string | null,
      resultDigest: await fingerprintJson(result),
    });
  }
  if (selection) {
    const development = records.filter((r) =>
      r.assignment.phase === "development"
    );
    check(
      development.length === 40 &&
        selection.developmentResultsDigest ===
          await fingerprintJson(development.map((r) => r.resultDigest)),
    );
    const actual = selectEvidenceCandidate(
      study.development,
      development.filter((r) => r.assignment.arm === "released").map((r) =>
        r.observation
      ),
      development.filter((r) => r.assignment.arm === "evidence").map((r) =>
        r.observation
      ),
    );
    check(
      await fingerprintJson(actual) ===
        await fingerprintJson(selection.selection),
    );
  }
  check(
    attempted <= P.maxAttempts &&
      settledNanoUsd + outstandingNanoUsd <= P.budgetNanoUsd,
  );
  return {
    attempted,
    settledNanoUsd,
    outstandingNanoUsd,
    stop,
    records,
    assignments,
    selection,
  };
}

export async function freezePhotoValidation(
  root: string,
  study: PhotoDecisionStudy,
) {
  const ledger = await readPhotoDecision(root, study);
  check(
    ledger.attempted === 40 && ledger.outstandingNanoUsd === 0 &&
      ledger.stop === null,
  );
  const observations = (arm: DecisionArm) =>
    ledger.records.filter((r) => r.assignment.arm === arm).map((r) =>
      r.observation
    );
  const selection = selectEvidenceCandidate(
    study.development,
    observations("released"),
    observations("evidence"),
  );
  const record = {
    version: "photo_decision_validation_freeze_v1",
    manifestDigest: study.digest,
    developmentResultsDigest: await fingerprintJson(
      ledger.records.map((r) => r.resultDigest),
    ),
    selection,
    arms: selection.selected
      ? ["released", "gemini", "evidence"]
      : ["released", "gemini"],
    assignmentsDigest: await fingerprintJson(
      study.manifest.assignments.filter((a) =>
        a.phase === "validation" && (selection.selected || a.arm !== "evidence")
      ),
    ),
  };
  const path = join(root, "validation-freeze.json");
  if (await exists(path)) {
    check(
      await fingerprintJson(await readJson(path)) ===
        await fingerprintJson(record),
    );
  } else await claimJson(path, record);
  return record;
}

export async function photoDecisionReport(
  root: string,
  study: PhotoDecisionStudy,
) {
  const ledger = await readPhotoDecision(root, study);
  const phaseReport = (phase: "development" | "validation") => {
    const cases = phase === "development"
      ? study.development
      : study.validation;
    const arms: DecisionArm[] = phase === "development"
      ? ["released", "evidence"]
      : ledger.selection?.selected
      ? ["released", "gemini", "evidence"]
      : ["released", "gemini"];
    const byArm = Object.fromEntries(arms.map((arm) => {
      const records = ledger.records.filter((r) =>
        r.assignment.phase === phase && r.assignment.arm === arm
      );
      const timings = records.map((r) => r.providerDurationMs).sort((a, b) =>
        a - b
      );
      return [arm, {
        ...decisionMetrics(cases, records.map((r) => r.observation)),
        attempted: records.length,
        meanProviderMs: timings.length
          ? timings.reduce((a, b) => a + b, 0) / timings.length
          : null,
        medianProviderMs: timings.length
          ? (timings[Math.floor((timings.length - 1) / 2)] +
            timings[Math.ceil((timings.length - 1) / 2)]) / 2
          : null,
        settledNanoUsd: records.reduce(
          (sum, r) => sum + (r.settledNanoUsd ?? 0),
          0,
        ),
      }];
    }));
    const success = (arm: DecisionArm) =>
      decisionRows(
        cases,
        ledger.records.filter((r) =>
          r.assignment.phase === phase && r.assignment.arm === arm
        ).map((r) => r.observation),
      ).map((r) => r.success);
    const complete =
      arms.every((arm) =>
        ledger.records.filter((r) =>
          r.assignment.phase === phase && r.assignment.arm === arm
        ).length === cases.length
      ) && ledger.stop === null;
    return {
      complete,
      arms: byArm,
      comparisons: Object.fromEntries(
        arms.filter((a) => a !== "released").map((arm) => {
          const paired = pairedDecision(success("released"), success(arm));
          return [arm, {
            ...paired,
            superiority: phase === "validation" && complete &&
              paired.superiority,
            confirmatory: phase === "validation" && complete,
          }];
        }),
      ),
    };
  };
  const next = ledger.assignments[ledger.attempted];
  const stop = ledger.stop ??
    (next &&
        ledger.settledNanoUsd + ledger.outstandingNanoUsd +
              next.reservedNanoUsd > P.budgetNanoUsd
      ? "budget_exhausted"
      : null);
  const report = {
    version: "photo_decision_report_v1",
    manifestDigest: study.digest,
    protocol: P,
    attempted: ledger.attempted,
    settledNanoUsd: ledger.settledNanoUsd,
    outstandingNanoUsd: ledger.outstandingNanoUsd,
    stop,
    complete: ledger.selection !== null &&
      ledger.attempted === ledger.assignments.length && stop === null,
    selection: ledger.selection,
    development: phaseReport("development"),
    validation: phaseReport("validation"),
    productionActivation: false,
    confidenceQualification: false,
  };
  await atomicJson(join(root, "decision-report.json"), report);
  return {
    report,
    next: stop ? null : next,
    selectionNeeded: !stop && ledger.attempted === 40 &&
      ledger.selection === null,
  };
}

export async function dispatchPhotoDecision(
  root: string,
  study: PhotoDecisionStudy,
  expectedArm: DecisionArm,
) {
  const { next: a, report } = await photoDecisionReport(root, study);
  check(a && a.arm === expectedArm && report.stop === null);
  for (const p of [study.openaiPricing, study.geminiPricing]) {
    const age = Date.now() - Date.parse(p.retrievedAt);
    check(age >= 0 && age <= 7 * 86400000);
  }
  check(Date.now() < Date.parse(String(study.plan.retainUntil)));
  const authorization = await privateDirectory(
    join(dirname(root), ".photo-decision-authorizations"),
  );
  const receiptPath = join(
    authorization,
    await fingerprintJson(study.plan.authorizationRef) + ".json",
  );
  const receipt = {
    version: P.version,
    rootDigest: study.plan.packetRootDigest,
    manifestDigest: study.digest,
  };
  if (await exists(receiptPath)) {
    check(
      await fingerprintJson(await readJson(receiptPath)) ===
        await fingerprintJson(receipt),
    );
  } else await claimJson(receiptPath, receipt);
  const c = study.corpus.cases.find((c) => c.input.caseId === a.caseId)!;
  const request = await prepareEvidence(root, c.input);
  const credential = await liveCredential(
    a.arm === "gemini" ? "gemini" : "openai",
  );
  const execution = a.arm === "gemini"
    ? await (await import("./providers.ts")).prepareEvaluationExecution(
      request,
      "gemini_pro",
      credential,
    )
    : a.arm === "evidence"
    ? createAIExecution(
      createOpenAIPhotoEvidenceEvaluationAdapter(credential),
      request,
      openAIPhotoEvidenceSnapshot(request),
    )
    : createAIExecution(
      createOpenAIConfidenceEvaluationAdapter(credential),
      request,
      openAIConfidenceSnapshot(request),
    );
  check(await fingerprintJson(execution.snapshot) === a.settingsDigest);
  const claim = claimFor(study, a),
    base = join(root, "decision-attempts", a.key);
  await claimJson(base + ".claim.json", claim);
  let outcome: AIProviderOutcome;
  try {
    outcome = await execution.invoke();
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
  const projected = a.arm === "gemini" ? null : projectConfidenceOutcome(
    a.caseId,
    outcome,
    study.taxonomy,
    study.openaiPricing,
  );
  const geminiRecord = a.arm === "gemini"
    ? projectOutcome(
      outcome,
      c.input,
      a.gemini!,
      study.digest,
      study.taxonomy,
      study.geminiPricing,
    )
    : null;
  const observation = projected?.observation ??
    parseConfidenceObservation({
      prediction: geminiRecord!.prediction,
      mapping: geminiRecord!.mapping,
    });
  const gCost = geminiRecord?.estimatedUpperUsd;
  const settledNanoUsd = projected
    ? projected.settledNanoUsd === null
      ? null
      : Math.ceil(projected.settledNanoUsd * 1.1)
    : gCost != null && outcome.returnedModel === "gemini-2.5-pro" &&
        !["unknown_execution", "operational_failure"].includes(outcome.kind)
    ? Math.ceil(gCost * 1e9)
    : null;
  if (settledNanoUsd !== null) integer(settledNanoUsd, 0, a.reservedNanoUsd);
  const named = observation.prediction.outcome === "normalized" &&
    observation.prediction.subject === "biological" &&
    observation.prediction.resolution === "named";
  let primaryNameDigest: string | null = null, nameForm: string | null = null;
  if (named && outcome.kind === "draft") {
    const normalized = a.arm === "gemini"
      ? normalizeEvaluationDraft(outcome.draft, c.input, "gemini_pro")
      : normalizeIdentification(outcome.draft, {
        hasVisualEvidence: true,
        hasAudioEvidence: false,
        hasInvasiveLocationContext: false,
        confidencePolicy: { kind: "unqualified" },
      });
    const name = normalizedTaxonomyName(
      normalized.identification.scientific_name!,
    );
    primaryNameDigest = await fingerprintJson(name);
    // Lexical diagnostic only; never infer rank or identity from spelling.
    nameForm = /[().×]|\b(?:sp|spp|cf|aff|complex|group)\b/u.test(name)
      ? "qualifier_or_annotation"
      : "plain";
  }
  await claimJson(base + ".result.json", {
    version: "photo_decision_result_v1",
    claimDigest: await fingerprintJson(claim),
    observation,
    accounting: projected?.accounting ?? null,
    geminiRecord,
    settledNanoUsd,
    providerDurationMs: outcome.providerDurationMs,
    primaryNameDigest,
    nameForm,
  });
  return await photoDecisionReport(root, study);
}
