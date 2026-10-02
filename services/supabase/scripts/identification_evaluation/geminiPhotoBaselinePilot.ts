/** Six Gemini calls against a frozen, completed OpenAI reasoning pilot. */
import { dirname, join } from "node:path";
import type { AIProviderOutcome } from "../../functions/_shared/ai/contracts.ts";
import { prepareEvidence } from "./assets.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  atomicJson,
  claimJson,
  exists,
  privateDirectory,
  readJson,
  withRunLock,
} from "./files.ts";
import { normalizeEvaluationDraft } from "./normalization.ts";
import { assignmentFor, estimateCost, modelPricing } from "./profiles.ts";
import { projectOutcome } from "./projection.ts";
import { parseReasoningPlan } from "./reasoningPilot.ts";
import {
  hash,
  parsePricing,
  type SourceIdentity,
  timestamp,
} from "./runContracts.ts";
import { validateRecord } from "./runner.ts";
import { assessReference } from "./scoring.ts";
import { normalizedTaxonomyName, parseTaxonomy } from "./taxonomy.ts";
import {
  fields,
  integer,
  member,
  requireCondition as check,
  token,
} from "./validation.ts";

export const GEMINI_BASELINE = {
  version: "gemini_photo_baseline_pilot_v1",
  profile: "gemini_pro",
  maxCalls: 6,
  cumulativeBudgetNanoUsd: 10_000_000_000,
} as const;

export async function prepareGeminiBaseline(
  root: string,
  source: SourceIdentity,
) {
  const plan = fields(await readJson(join(root, "gemini-plan.json")), [
    "version",
    "mode",
    "authorizationRef",
    "packetRootDigest",
    "baselineReportDigest",
    "retainUntil",
    "paidServiceApproved",
    "inputPermission",
  ]);
  check(plan.version === GEMINI_BASELINE.version);
  member(plan.mode, ["offline", "live"]);
  token(plan.authorizationRef);
  hash(plan.packetRootDigest);
  hash(plan.baselineReportDigest);
  timestamp(plan.retainUntil);
  check(plan.paidServiceApproved === true && plan.inputPermission === "gemini");
  check(
    plan.packetRootDigest === await fingerprintJson(await Deno.realPath(root)),
  );
  const baseline = fields(await readJson(join(root, "baseline-report.json")), [
    "version",
    "manifestDigest",
    "sourceDigest",
    "mode",
    "scheduled",
    "budgetNanoUsd",
    "attempted",
    "settledNanoUsd",
    "outstandingNanoUsd",
    "stop",
    "records",
    "complete",
    "confidenceQualification",
    "productionActivation",
  ]);
  check(await fingerprintJson(baseline) === plan.baselineReportDigest);
  check(
    baseline.version === "openai_photo_reasoning_report_v1" &&
      baseline.complete === true && baseline.stop === null &&
      baseline.scheduled === 12 && baseline.attempted === 12 &&
      baseline.outstandingNanoUsd === 0 && baseline.mode === plan.mode,
  );
  integer(baseline.settledNanoUsd, 0, GEMINI_BASELINE.cumulativeBudgetNanoUsd);
  const original = parseReasoningPlan(
    await readJson(join(root, "baseline-plan.json")),
  );
  check(original.mode === plan.mode);
  const baselineManifest = fields(
    await readJson(join(root, "baseline-manifest.json")),
    [
      "version",
      "sourceDigest",
      "protocol",
      "planDigest",
      "taxonomyDigest",
      "pricingDigest",
      "assignments",
    ],
  );
  const taxonomy = parseTaxonomy(await readJson(join(root, "taxonomy.json")));
  check(taxonomy.version === "evaluation_taxonomy_v2");
  check(
    baseline.manifestDigest === await fingerprintJson(baselineManifest) &&
      baselineManifest.planDigest === await fingerprintJson(original) &&
      baselineManifest.taxonomyDigest === await fingerprintJson(taxonomy),
  );
  const pricing = parsePricing(await readJson(join(root, "pricing.json")));
  const price = modelPricing(pricing, "gemini-2.5-pro");
  // Reserve the entire model input/output ceilings, including thinking. This is
  // deliberately conservative; actual complete usage releases the remainder.
  check(
    price.maxInputTokens >= 1_048_576 &&
      price.maxBillableOutputTokens >= 65_536,
  );
  const assignments = [];
  for (const [index, caseIndex] of [0, 0, 0, 1, 2, 3].entries()) {
    const c = original.cases[caseIndex];
    check(
      c.input.context.deviceRegion === null &&
        c.input.context.currentMonth === null,
    );
    const request = await prepareEvidence(root, c.input);
    const assignment = await assignmentFor(
      c.input,
      request,
      "gemini_pro",
      index + 1,
      pricing,
    );
    const reservation = Math.ceil(assignment.reservedUsd * 1e9);
    integer(reservation, 1, GEMINI_BASELINE.cumulativeBudgetNanoUsd);
    assignments.push({
      ordinal: index + 1,
      assignment,
      reservedNanoUsd: reservation,
    });
  }
  const manifest = {
    version: "gemini_photo_baseline_manifest_v1",
    protocol: GEMINI_BASELINE,
    source,
    planDigest: await fingerprintJson(plan),
    baselineReportDigest: plan.baselineReportDigest,
    baselineManifestDigest: baseline.manifestDigest,
    priorNanoUsd: baseline.settledNanoUsd,
    taxonomyDigest: await fingerprintJson(taxonomy),
    pricingDigest: await fingerprintJson(pricing),
    assignments,
  };
  const path = join(root, "gemini-manifest.json");
  if (await exists(path)) {
    check(
      await fingerprintJson(await readJson(path)) ===
        await fingerprintJson(manifest),
    );
  } else await claimJson(path, manifest);
  return {
    plan,
    cases: original.cases,
    taxonomy,
    pricing,
    manifest,
    digest: await fingerprintJson(manifest),
  };
}
export type PreparedGeminiBaseline = Awaited<
  ReturnType<typeof prepareGeminiBaseline>
>;
const slotName = (ordinal: number) => String(ordinal).padStart(2, "0");
const claimFor = (
  pilot: PreparedGeminiBaseline,
  a: PreparedGeminiBaseline["manifest"]["assignments"][number],
) => ({
  version: "gemini_photo_baseline_claim_v1",
  manifestDigest: pilot.digest,
  assignment: a,
});

export async function bindGeminiBaseline(
  root: string,
  pilot: PreparedGeminiBaseline,
) {
  const directory = await privateDirectory(
    join(dirname(root), ".gemini-baseline-authorizations"),
  );
  const path = join(
    directory,
    await fingerprintJson(pilot.plan.authorizationRef) + ".json",
  );
  const receipt = {
    version: GEMINI_BASELINE.version,
    rootDigest: pilot.plan.packetRootDigest,
    manifestDigest: pilot.digest,
  };
  if (!await exists(path)) await claimJson(path, receipt);
  check(
    await fingerprintJson(await readJson(path)) ===
      await fingerprintJson(receipt),
  );
}

export async function readGeminiBaseline(
  root: string,
  pilot: PreparedGeminiBaseline,
) {
  const directory = await privateDirectory(join(root, "gemini-attempts"));
  const allowed = pilot.manifest.assignments.flatMap((a) =>
    ["claim", "result"].map((s) => `${slotName(a.ordinal)}.${s}.json`)
  );
  for await (const entry of Deno.readDir(directory)) {
    check(entry.isFile && !entry.isSymlink && allowed.includes(entry.name));
  }
  let attempted = 0, settledNanoUsd = 0, outstandingNanoUsd = 0;
  let stop: string | null = null;
  const records = [];
  for (const a of pilot.manifest.assignments) {
    const base = join(directory, slotName(a.ordinal));
    if (!await exists(base + ".claim.json")) {
      check(!await exists(base + ".result.json"));
      continue;
    }
    check(a.ordinal === attempted + 1 && stop === null);
    const claim = claimFor(pilot, a);
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
      "record",
      "primaryNameDigest",
    ]);
    check(
      result.version === "gemini_photo_baseline_result_v1" &&
        result.claimDigest === await fingerprintJson(claim),
    );
    const record = validateRecord(
      result.record,
      a.assignment,
      pilot.digest,
      pilot.pricing,
      true,
    );
    const cost = estimateCost(pilot.pricing, a.assignment.model, record.usage);
    check(cost === record.estimatedUpperUsd);
    const accountingKnown = record.returnedModel === a.assignment.model &&
      record.prediction.outcome !== "unknown_execution" &&
      record.prediction.outcome !== "operational_failure";
    const settled = cost === null || !accountingKnown
      ? null
      : Math.ceil(cost * 1e9);
    check(settled === null || settled <= a.reservedNanoUsd);
    if (settled === null) {
      outstandingNanoUsd += a.reservedNanoUsd;
      stop = "accounting_incomplete";
    } else settledNanoUsd += settled;
    if (record.reason !== "completed") stop ??= record.reason;
    const named = record.prediction.outcome === "normalized" &&
      record.prediction.resolution === "named";
    check(named === (result.primaryNameDigest !== null));
    if (result.primaryNameDigest !== null) hash(result.primaryNameDigest);
    const reference = pilot.cases.find((c) =>
      c.input.caseId === a.assignment.caseId
    )!.reference;
    records.push({
      ordinal: a.ordinal,
      record,
      primaryNameDigest: result.primaryNameDigest,
      assessment: reference
        ? assessReference(reference, record.prediction)
        : null,
    });
  }
  const cumulativeNanoUsd = pilot.manifest.priorNanoUsd + settledNanoUsd +
    outstandingNanoUsd;
  check(cumulativeNanoUsd <= GEMINI_BASELINE.cumulativeBudgetNanoUsd);
  return {
    attempted,
    settledNanoUsd,
    outstandingNanoUsd,
    cumulativeNanoUsd,
    stop,
    records,
  };
}

export async function saveGeminiBaseline(
  root: string,
  pilot: PreparedGeminiBaseline,
  stop: string | null = null,
) {
  const ledger = await readGeminiBaseline(root, pilot);
  const report = {
    version: "gemini_photo_baseline_report_v1",
    manifestDigest: pilot.digest,
    baselineReportDigest: pilot.plan.baselineReportDigest,
    mode: pilot.plan.mode,
    scheduled: 6,
    priorNanoUsd: pilot.manifest.priorNanoUsd,
    cumulativeBudgetNanoUsd: GEMINI_BASELINE.cumulativeBudgetNanoUsd,
    ...ledger,
    stop: ledger.stop ?? stop,
    complete: ledger.attempted === 6 && ledger.stop === null,
    confidenceQualification: false,
    productionActivation: false,
  };
  await atomicJson(join(root, "gemini-report.json"), report);
  return report;
}

export async function executeGeminiBaseline(
  root: string,
  source: SourceIdentity,
  mode: "live" | "offline",
  offlineOutcome?: (ordinal: number) => Promise<AIProviderOutcome>,
) {
  check(mode === "offline" ? !!offlineOutcome : offlineOutcome === undefined);
  return await withRunLock(root, async () => {
    if (mode === "live") {
      check(await exists(join(root, "gemini-manifest.json")));
    }
    const pilot = await prepareGeminiBaseline(root, source);
    check(pilot.plan.mode === mode);
    if (mode === "live") await bindGeminiBaseline(root, pilot);
    for (const a of pilot.manifest.assignments) {
      const ledger = await readGeminiBaseline(root, pilot);
      if (ledger.stop) return await saveGeminiBaseline(root, pilot);
      if (a.ordinal <= ledger.attempted) continue;
      if (
        ledger.cumulativeNanoUsd + a.reservedNanoUsd >
          GEMINI_BASELINE.cumulativeBudgetNanoUsd
      ) {
        return await saveGeminiBaseline(root, pilot, "budget_exhausted");
      }
      if (mode === "live") {
        const age = Date.now() - Date.parse(pilot.pricing.retrievedAt);
        check(
          age >= 0 && age <= 7 * 86400000 &&
            Date.now() < Date.parse(String(pilot.plan.retainUntil)),
        );
      }
      check(
        (await prepareGeminiBaseline(root, source)).digest === pilot.digest,
      );
      const c = pilot.cases.find((c) =>
        c.input.caseId === a.assignment.caseId
      )!;
      const request = await prepareEvidence(root, c.input);
      const execution = mode === "live"
        ? await (await import("./providers.ts")).prepareEvaluationExecution(
          request,
          "gemini_pro",
          await (await import("./admission.ts")).liveCredential("gemini"),
        )
        : null;
      if (execution) {
        check(
          await fingerprintJson(execution.snapshot) ===
            a.assignment.policyDigest,
        );
      }
      const base = join(root, "gemini-attempts", slotName(a.ordinal));
      const claim = claimFor(pilot, a);
      await claimJson(base + ".claim.json", claim);
      let outcome: AIProviderOutcome;
      try {
        outcome = execution
          ? await execution.invoke()
          : await offlineOutcome!(a.ordinal);
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
      const record = projectOutcome(
        outcome,
        c.input,
        a.assignment,
        pilot.digest,
        pilot.taxonomy,
        pilot.pricing,
      );
      const named = record.prediction.outcome === "normalized" &&
        record.prediction.resolution === "named";
      const primaryNameDigest = named && outcome.kind === "draft"
        ? await fingerprintJson(normalizedTaxonomyName(
          normalizeEvaluationDraft(outcome.draft, c.input, "gemini_pro")
            .identification.scientific_name!,
        ))
        : null;
      await claimJson(base + ".result.json", {
        version: "gemini_photo_baseline_result_v1",
        claimDigest: await fingerprintJson(claim),
        record,
        primaryNameDigest,
      });
      await saveGeminiBaseline(root, pilot);
    }
    return await saveGeminiBaseline(root, pilot);
  });
}
