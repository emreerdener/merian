import { dirname, join } from "node:path";
import type { AIProviderOutcome } from "../../functions/_shared/ai/contracts.ts";
import { createAIExecution } from "../../functions/_shared/ai/execution.ts";
import {
  createOpenAIPhotoReasoningEvaluationAdapter,
} from "../../functions/_shared/ai/openai.ts";
import {
  buildOpenAIPhotoReasoningRequest,
  openAIPhotoReasoningSnapshot,
} from "../../functions/_shared/ai/openaiPhotoReasoning.ts";
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
import { assignmentFor, estimateCost } from "./profiles.ts";
import { projectOutcome } from "./projection.ts";
import { validateRecord } from "./runner.ts";
import { hash } from "./runContracts.ts";
import { normalizedTaxonomyName } from "./taxonomy.ts";
import { fields, integer, requireCondition as check } from "./validation.ts";
import {
  TRADEOFF as P,
  type TradeoffArm,
  type TradeoffAssignment,
  type TradeoffStudy,
} from "./reasoningTradeoffPreparation.ts";
import { tradeoffStatistics } from "./reasoningTradeoffStatistics.ts";
const claimFor = (study: TradeoffStudy, a: TradeoffAssignment) => ({
  version: "photo_reasoning_tradeoff_claim_v1",
  manifestDigest: study.digest,
  assignment: a,
});

export async function readReasoningTradeoff(
  root: string,
  study: TradeoffStudy,
) {
  const directory = await privateDirectory(join(root, "tradeoff-attempts"));
  const assignments = study.manifest.assignments;
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
    assignment: TradeoffAssignment;
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
      result.version === "photo_reasoning_tradeoff_result_v1" &&
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
    if (observation.prediction.outcome !== "normalized") {
      stop ??= "provider_failure";
    }
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
  check(
    attempted <= P.maxAttempts &&
      settledNanoUsd + outstandingNanoUsd <= P.budgetNanoUsd,
  );
  const next = assignments[attempted];
  if (
    !stop && next &&
    settledNanoUsd + outstandingNanoUsd + next.reservedNanoUsd > P.budgetNanoUsd
  ) stop = "budget_exhausted";
  return {
    attempted,
    settledNanoUsd,
    outstandingNanoUsd,
    stop,
    records,
    next: stop ? null : next ?? null,
  };
}

export async function reasoningTradeoffReport(
  root: string,
  study: TradeoffStudy,
) {
  const ledger = await readReasoningTradeoff(root, study);
  const statistics = tradeoffStatistics(
    study.cases,
    ledger.records.map((r) => ({
      arm: r.assignment.arm,
      observation: r.observation,
      providerDurationMs: r.providerDurationMs,
    })),
  );
  const complete = ledger.attempted === P.maxAttempts && ledger.stop === null;
  const report = {
    version: "photo_reasoning_tradeoff_report_v1",
    manifestDigest: study.digest,
    protocol: P,
    mode: study.plan.mode,
    attempted: ledger.attempted,
    settledNanoUsd: ledger.settledNanoUsd,
    outstandingNanoUsd: ledger.outstandingNanoUsd,
    stop: ledger.stop,
    complete,
    statistics,
    advancesToFreshValidation: complete && study.plan.mode === "live" &&
      statistics.advancesToFreshValidation,
    productionActivation: false,
    confidenceQualification: false,
  };
  await atomicJson(join(root, "tradeoff-report.json"), report);
  return { report, next: ledger.next };
}

export async function bindTradeoffAuthorization(
  root: string,
  study: TradeoffStudy,
) {
  check(
    study.plan.packetRootDigest ===
      await fingerprintJson(await Deno.realPath(root)),
  );
  const directory = await privateDirectory(
    join(dirname(root), ".reasoning-tradeoff-authorizations"),
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
  if (await exists(path)) {
    check(
      await fingerprintJson(await readJson(path)) ===
        await fingerprintJson(receipt),
    );
  } else await claimJson(path, receipt);
}

/** Caller holds withRunLock and rebuilds the manifest from actual source before entry.
 * Synthetic injection is allowed only for an offline packet, never by the live CLI.
 */
export async function dispatchReasoningTradeoff(
  root: string,
  study: TradeoffStudy,
  expectedArm: TradeoffArm,
  syntheticInvoke?: () => Promise<AIProviderOutcome>,
) {
  const { next: a, report } = await reasoningTradeoffReport(root, study);
  check(a && a.arm === expectedArm && report.stop === null);
  check(Date.now() < Date.parse(String(study.plan.retainUntil)));
  const c = study.cases.find((c) => c.input.caseId === a.caseId)!;
  const request = await prepareEvidence(root, c.input);
  if (a.arm === "gemini") {
    const rebuilt = await assignmentFor(
      c.input,
      request,
      "gemini_pro",
      1,
      study.geminiPricing,
    );
    check(
      rebuilt.requestDigest === a.requestDigest &&
        rebuilt.policyDigest === a.settingsDigest,
    );
  } else {
    const rebuilt = openAIPhotoReasoningSnapshot(request, a.arm);
    check(
      await fingerprintJson(rebuilt) === a.settingsDigest &&
        await fingerprintJson(
            buildOpenAIPhotoReasoningRequest(request, rebuilt),
          ) === a.requestDigest,
    );
  }
  let invoke: () => Promise<AIProviderOutcome>;
  if (syntheticInvoke) {
    check(
      study.plan.mode === "offline" && study.plan.paidServiceApproved === false,
    );
    invoke = syntheticInvoke;
  } else {
    check(
      study.plan.mode === "live" && study.plan.paidServiceApproved === true &&
        !study.manifest.source.dirty,
    );
    for (const p of [study.openaiPricing, study.geminiPricing]) {
      const age = Date.now() - Date.parse(p.retrievedAt);
      check(age >= 0 && age <= 7 * 86400000);
    }
    const provider = a.arm === "gemini" ? "gemini" : "openai";
    const credential = await liveCredential(provider);
    const bindings = fields(study.plan.credentialDigests, ["openai", "gemini"]);
    check(await fingerprintJson(credential) === bindings[provider]);
    await bindTradeoffAuthorization(root, study);
    const execution = a.arm === "gemini"
      ? await (await import("./providers.ts")).prepareEvaluationExecution(
        request,
        "gemini_pro",
        credential,
      )
      : createAIExecution(
        createOpenAIPhotoReasoningEvaluationAdapter(credential),
        request,
        openAIPhotoReasoningSnapshot(request, a.arm),
      );
    check(await fingerprintJson(execution.snapshot) === a.settingsDigest);
    invoke = () => execution.invoke();
  }
  const claim = claimFor(study, a),
    base = join(root, "tradeoff-attempts", a.key);
  await claimJson(base + ".claim.json", claim);
  let outcome: AIProviderOutcome;
  try {
    outcome = await invoke();
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
    version: "photo_reasoning_tradeoff_result_v1",
    claimDigest: await fingerprintJson(claim),
    observation,
    accounting: projected?.accounting ?? null,
    geminiRecord,
    settledNanoUsd,
    providerDurationMs: outcome.providerDurationMs,
    primaryNameDigest,
    nameForm,
  });
  return await reasoningTradeoffReport(root, study);
}
