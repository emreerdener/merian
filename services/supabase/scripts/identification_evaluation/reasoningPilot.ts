/** A small effort-only comparison, separate from the completed confidence study. */
import { dirname, join } from "node:path";
import type {
  AIAdapter,
  AIProviderOutcome,
} from "../../functions/_shared/ai/contracts.ts";
import { createAIExecution } from "../../functions/_shared/ai/execution.ts";
import { normalizeIdentification } from "../../functions/_shared/identify/normalizeIdentification.ts";
import {
  buildOpenAIPhotoReasoningRequest,
  openAIPhotoReasoningSnapshot,
  type PhotoReasoningEffort,
} from "../../functions/_shared/ai/openaiPhotoReasoning.ts";
import { prepareEvidence } from "./assets.ts";
import type { EvaluationInput, ReferenceLabel } from "./contracts.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  atomicJson,
  claimJson,
  exists,
  privateDirectory,
  readJson,
  withRunLock,
} from "./files.ts";
import {
  hash,
  parseEvaluationPricing,
  type SourceIdentity,
} from "./runContracts.ts";
import { reserveCost } from "./profiles.ts";
import { normalizedTaxonomyName, parseTaxonomy } from "./taxonomy.ts";
import {
  confidenceCost,
  parseConfidenceAccounting,
} from "./confidenceAccounting.ts";
import { projectConfidenceOutcome } from "./confidenceProjection.ts";
import { parseConfidenceObservation } from "./confidenceScoring.ts";
import { confidencePricingCurrent } from "./confidencePreparation.ts";
import { parseRatings, type Ratings } from "./explanationContracts.ts";
import type { ReviewDisplay } from "./explanationView.ts";
import { assessReference } from "./scoring.ts";
import {
  array,
  fields,
  member,
  parseEvaluationInput,
  requireCondition as check,
  text,
  token,
  validateReference,
} from "./validation.ts";

export const REASONING_PILOT = {
  version: "openai_photo_reasoning_pilot_v1",
  maxCalls: 12,
  budgetNanoUsd: 10_000_000_000,
  billingMultiplier: 1.1,
} as const;
export interface ReasoningCase {
  input: EvaluationInput;
  reference: ReferenceLabel | null;
  facts: string[];
  evidenceRef: string;
  rightsApproved: true;
  personalDataExcluded: true;
}
export interface ReasoningPlan {
  version: typeof REASONING_PILOT.version;
  mode: "live" | "offline";
  authorizationRef: string;
  packetRootDigest: string;
  cases: ReasoningCase[];
}
export function parseReasoningPlan(value: unknown): ReasoningPlan {
  const p = fields(value, [
    "version",
    "mode",
    "authorizationRef",
    "packetRootDigest",
    "cases",
  ]);
  check(p.version === REASONING_PILOT.version);
  member(p.mode, ["live", "offline"]);
  token(p.authorizationRef);
  hash(p.packetRootDigest);
  const ids = new Set<string>(), assets = new Set<string>();
  for (const [i, raw] of array(p.cases, 4, 4).entries()) {
    const c = fields(raw, [
      "input",
      "reference",
      "facts",
      "evidenceRef",
      "rightsApproved",
      "personalDataExcluded",
    ]);
    const input = parseEvaluationInput(c.input);
    check(
      input.inputGroup === "photos" && input.assets.length === 1 &&
        input.observationTexts.length === 0 && input.split === "development",
    );
    check(!ids.has(input.caseId) && !assets.has(input.assets[0].sha256));
    ids.add(input.caseId);
    assets.add(input.assets[0].sha256);
    check(c.rightsApproved === true && c.personalDataExcluded === true);
    token(c.evidenceRef);
    array(c.facts, 1, 16).forEach((v) => text(v));
    // The owner-supplied photo has no independent reference: consistency only.
    if (i === 0) check(c.reference === null);
    else validateReference(c.reference, p.mode === "offline");
  }
  return structuredClone(p) as unknown as ReasoningPlan;
}

export async function prepareReasoningPilot(
  root: string,
  source: SourceIdentity,
) {
  const plan = parseReasoningPlan(
    await readJson(join(root, "reasoning-plan.json")),
  );
  check(
    plan.packetRootDigest === await fingerprintJson(await Deno.realPath(root)),
  );
  const taxonomy = parseTaxonomy(await readJson(join(root, "taxonomy.json")));
  check(taxonomy.version === "evaluation_taxonomy_v2");
  const pricing = parseEvaluationPricing(
    await readJson(join(root, "pricing.json")),
  );
  check(pricing.version === "evaluation_openai_pricing_v1");
  const price = pricing.models.find((p) => p.model === "gpt-6-sol");
  check(
    price && price.maxInputTokens >= 1_050_000 &&
      price.maxBillableOutputTokens >= 8192,
  );
  const reservedNanoUsd = Math.ceil(
    reserveCost(pricing, "gpt-6-sol") * 1e9 * REASONING_PILOT.billingMultiplier,
  );
  check(
    Number.isSafeInteger(reservedNanoUsd) && reservedNanoUsd > 0 &&
      reservedNanoUsd <= REASONING_PILOT.budgetNanoUsd,
  );
  const assignments = [];
  // Three independent pairs on the supplied photo, then three reference pairs.
  // Alternate first effort to reduce order effects. Every slot is predeclared.
  for (const [pair, caseIndex] of [0, 0, 0, 1, 2, 3].entries()) {
    const c = plan.cases[caseIndex],
      request = await prepareEvidence(root, c.input);
    const efforts: PhotoReasoningEffort[] = pair % 2
      ? ["medium", "low"]
      : ["low", "medium"];
    for (const effort of efforts) {
      const snapshot = openAIPhotoReasoningSnapshot(request, effort);
      const parameters = buildOpenAIPhotoReasoningRequest(request, snapshot);
      const { input: _input, ...settings } = parameters;
      assignments.push({
        ordinal: assignments.length + 1,
        caseId: c.input.caseId,
        pair: pair + 1,
        effort,
        requestDigest: await fingerprintJson(parameters),
        settingsDigest: await fingerprintJson({ snapshot, settings }),
        reservedNanoUsd,
      });
    }
  }
  const manifest = {
    version: "openai_photo_reasoning_manifest_v1",
    sourceDigest: source.digest,
    protocol: REASONING_PILOT,
    planDigest: await fingerprintJson(plan),
    taxonomyDigest: await fingerprintJson(taxonomy),
    pricingDigest: await fingerprintJson(pricing),
    assignments,
  };
  const path = join(root, "reasoning-manifest.json");
  if (await exists(path)) {
    check(
      await fingerprintJson(await readJson(path)) ===
        await fingerprintJson(manifest),
    );
  } else await claimJson(path, manifest);
  return {
    plan,
    taxonomy,
    pricing,
    manifest,
    digest: await fingerprintJson(manifest),
  };
}
export type PreparedReasoningPilot = Awaited<
  ReturnType<typeof prepareReasoningPilot>
>;

/** Sibling receipt prevents copied packets from reusing this run authorization. */
export async function bindReasoningAuthorization(
  root: string,
  pilot: PreparedReasoningPilot,
) {
  check(
    pilot.plan.packetRootDigest ===
      await fingerprintJson(await Deno.realPath(root)),
  );
  const directory = await privateDirectory(
    join(dirname(root), ".reasoning-authorizations"),
  );
  const key = await fingerprintJson(pilot.plan.authorizationRef);
  const path = join(directory, key + ".json");
  const expected = {
    version: "openai_reasoning_authorization_v1",
    rootDigest: await fingerprintJson(await Deno.realPath(root)),
    manifestDigest: pilot.digest,
    protocol: REASONING_PILOT,
  };
  if (!await exists(path)) await claimJson(path, expected);
  check(
    await fingerprintJson(await readJson(path)) ===
      await fingerprintJson(expected),
  );
}
const name = (ordinal: number) => String(ordinal).padStart(2, "0");
const resultKeys = [
  "version",
  "claimDigest",
  "observation",
  "accounting",
  "settledNanoUsd",
  "durationMs",
  "primaryNameDigest",
];
const regionalCost = (n: number | null) =>
  n === null ? null : Math.ceil(n * REASONING_PILOT.billingMultiplier);

export async function readReasoningLedger(
  root: string,
  pilot: PreparedReasoningPilot,
) {
  const directory = await privateDirectory(join(root, "reasoning-attempts"));
  const allowed = pilot.manifest.assignments.flatMap((a) =>
    ["claim", "result", "review"].map((s) => `${name(a.ordinal)}.${s}.json`)
  );
  for await (const e of Deno.readDir(directory)) {
    check(e.isFile && !e.isSymlink && allowed.includes(e.name));
  }
  let attempted = 0, settledNanoUsd = 0, outstandingNanoUsd = 0;
  let stop: string | null = null;
  const records = [];
  for (const a of pilot.manifest.assignments) {
    const base = join(directory, name(a.ordinal));
    if (!await exists(`${base}.claim.json`)) {
      check(
        !await exists(`${base}.result.json`) &&
          !await exists(`${base}.review.json`),
      );
      continue;
    }
    check(a.ordinal === attempted + 1 && stop === null);
    const claim = {
      version: "openai_photo_reasoning_claim_v1",
      manifestDigest: pilot.digest,
      assignment: a,
    };
    check(
      await fingerprintJson(await readJson(`${base}.claim.json`)) ===
        await fingerprintJson(claim),
    );
    attempted++;
    if (!await exists(`${base}.result.json`)) {
      outstandingNanoUsd += a.reservedNanoUsd;
      stop = "interrupted_attempt";
      continue;
    }
    const raw = fields(await readJson(`${base}.result.json`), resultKeys);
    check(
      raw.version === "openai_photo_reasoning_result_v1" &&
        raw.claimDigest === await fingerprintJson(claim),
    );
    const observation = parseConfidenceObservation(raw.observation);
    check(observation.prediction.caseId === a.caseId);
    if (raw.primaryNameDigest !== null) hash(raw.primaryNameDigest);
    check(
      (observation.prediction.outcome === "normalized" &&
        observation.prediction.resolution === "named") ===
        (raw.primaryNameDigest !== null),
    );
    const accounting = parseConfidenceAccounting(raw.accounting);
    const cost = regionalCost(confidenceCost(accounting, pilot.pricing));
    check(
      cost === raw.settledNanoUsd &&
        (cost === null || cost <= a.reservedNanoUsd),
    );
    check(
      typeof raw.durationMs === "number" && Number.isFinite(raw.durationMs) &&
        raw.durationMs >= 0,
    );
    if (cost === null) {
      outstandingNanoUsd += a.reservedNanoUsd;
      stop = "accounting_incomplete";
    } else settledNanoUsd += cost;
    let ratings: Ratings | null = null;
    if (await exists(`${base}.review.json`)) {
      const r = fields(await readJson(`${base}.review.json`), [
        "resultDigest",
        "ratings",
      ]);
      check(r.resultDigest === await fingerprintJson(raw));
      ratings = parseRatings(r.ratings);
    }
    if (observation.prediction.outcome === "normalized" && ratings === null) {
      stop ??= "review_incomplete";
    }
    if (observation.prediction.outcome !== "normalized") {
      stop ??= "provider_failure";
    }
    const reference = pilot.plan.cases.find((c) =>
      c.input.caseId === a.caseId
    )!.reference;
    records.push({
      ordinal: a.ordinal,
      caseId: a.caseId,
      effort: a.effort,
      observation,
      ratings,
      primaryNameDigest: raw.primaryNameDigest as string | null,
      durationMs: raw.durationMs,
      settledNanoUsd: cost,
      assessment: reference
        ? assessReference(reference, observation.prediction)
        : null,
    });
  }
  check(settledNanoUsd + outstandingNanoUsd <= REASONING_PILOT.budgetNanoUsd);
  return { attempted, settledNanoUsd, outstandingNanoUsd, stop, records };
}

export async function saveReasoningReport(
  root: string,
  pilot: PreparedReasoningPilot,
  stop: string | null = null,
) {
  const ledger = await readReasoningLedger(root, pilot);
  const report = {
    version: "openai_photo_reasoning_report_v1",
    manifestDigest: pilot.digest,
    sourceDigest: pilot.manifest.sourceDigest,
    mode: pilot.plan.mode,
    scheduled: REASONING_PILOT.maxCalls,
    budgetNanoUsd: REASONING_PILOT.budgetNanoUsd,
    ...ledger,
    stop: ledger.stop ?? stop,
    complete: ledger.attempted === 12 && ledger.stop === null,
    confidenceQualification: false,
    productionActivation: false,
  };
  await atomicJson(join(root, "reasoning-report.json"), report);
  return report;
}

export async function executeReasoningPilot(
  root: string,
  source: SourceIdentity,
  mode: "live" | "offline",
  adapter: AIAdapter<ReturnType<typeof openAIPhotoReasoningSnapshot>>,
  review: (display: ReviewDisplay | null) => Promise<Ratings | null>,
) {
  return await withRunLock(root, async () => {
    if (mode === "live") {
      check(await exists(join(root, "reasoning-manifest.json")));
    }
    const pilot = await prepareReasoningPilot(root, source);
    check(pilot.plan.mode === mode);
    if (mode === "live") await bindReasoningAuthorization(root, pilot);
    for (const a of pilot.manifest.assignments) {
      const ledger = await readReasoningLedger(root, pilot);
      if (ledger.stop) return await saveReasoningReport(root, pilot);
      if (a.ordinal <= ledger.attempted) continue;
      if (
        ledger.settledNanoUsd + ledger.outstandingNanoUsd + a.reservedNanoUsd >
          REASONING_PILOT.budgetNanoUsd
      ) {
        return await saveReasoningReport(root, pilot, "budget_exhausted");
      }
      check(
        mode === "offline" ||
          confidencePricingCurrent(pilot.pricing, Date.now()),
      );
      // Recheck media, references, pricing, and exact request before every claim.
      check(
        (await prepareReasoningPilot(root, source)).digest === pilot.digest,
      );
      const c = pilot.plan.cases.find((c) => c.input.caseId === a.caseId)!;
      const request = await prepareEvidence(root, c.input);
      const snapshot = openAIPhotoReasoningSnapshot(request, a.effort);
      const execution = createAIExecution(adapter, request, snapshot);
      const base = join(root, "reasoning-attempts", name(a.ordinal));
      const claim = {
        version: "openai_photo_reasoning_claim_v1",
        manifestDigest: pilot.digest,
        assignment: a,
      };
      await claimJson(`${base}.claim.json`, claim);
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
      const projected = projectConfidenceOutcome(
        a.caseId,
        outcome,
        pilot.taxonomy,
        pilot.pricing,
      );
      const normalized =
        projected.observation.prediction.outcome === "normalized" &&
          outcome.kind === "draft"
          ? normalizeIdentification(outcome.draft, {
            hasVisualEvidence: true,
            hasAudioEvidence: false,
            hasInvasiveLocationContext: false,
            confidencePolicy: { kind: "unqualified" },
          })
          : null;
      const result = {
        version: "openai_photo_reasoning_result_v1",
        claimDigest: await fingerprintJson(claim),
        observation: projected.observation,
        accounting: projected.accounting,
        settledNanoUsd: regionalCost(projected.settledNanoUsd),
        durationMs: outcome.providerDurationMs,
        primaryNameDigest:
          projected.observation.prediction.outcome === "normalized" &&
            projected.observation.prediction.resolution === "named" &&
            normalized?.identification.scientific_name
            ? await fingerprintJson(
              normalizedTaxonomyName(normalized.identification.scientific_name),
            )
            : null,
      };
      await claimJson(`${base}.result.json`, result);
      if (
        normalized !== null && result.settledNanoUsd !== null
      ) {
        const v = normalized.identification;
        // Full text stays in the one-use local view. Only enum ratings are saved.
        const display: ReviewDisplay = {
          reviewerKind: "assistant",
          title: `Reasoning comparison review ${a.ordinal} of 12`,
          observation: [],
          facts: c.facts,
          images: request.evidence.filter((e) => e.kind === "image").map((
            e,
          ) => ({ mimeType: e.mimeType, data: e.data })),
          decision: [
            v.is_biological_subject ? "Biological" : "Nonbiological",
            v.scientific_name ?? "Unresolved",
          ],
          explanation: [
            v.ai_reasoning ?? "",
            ...(v.extracted_visual_traits ?? []),
            ...(normalized.clientCandidates ?? []).map((x) =>
              `${x.scientific_name}: ${x.distinguishing_feature ?? ""}`
            ),
          ],
        };
        const ratings = await review(display);
        if (ratings !== null) {
          await claimJson(`${base}.review.json`, {
            resultDigest: await fingerprintJson(result),
            ratings: parseRatings(ratings),
          });
        }
      }
      await saveReasoningReport(root, pilot);
    }
    return await saveReasoningReport(root, pilot);
  });
}
