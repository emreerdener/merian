/** New development study. Never reads or reopens a historical authorization. */
import { join } from "node:path";
import {
  buildOpenAIConfidenceRequest,
  openAIConfidenceSnapshot,
} from "../../functions/_shared/ai/openaiPhotoConfidence.ts";
import {
  buildOpenAIPhotoReasoningRequest,
  openAIPhotoReasoningSnapshot,
} from "../../functions/_shared/ai/openaiPhotoReasoning.ts";
import { prepareEvidence } from "./assets.ts";
import type { ScoringCase } from "./confidenceScoring.ts";
import { CONFIDENCE_PROTOCOL } from "./confidenceProtocol.ts";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import { FEATURE_ADJUDICATION_SHA256 } from "./photoFeaturePreparation.ts";
import { claimJson, exists, readJson } from "./files.ts";
import { assignmentFor, random, reserveCost } from "./profiles.ts";
import {
  hash,
  parseEvaluationPricing,
  parsePricing,
  type SourceIdentity,
  timestamp,
} from "./runContracts.ts";
import { parseTaxonomy } from "./taxonomy.ts";
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

export const TRADEOFF = Object.freeze({
  version: "photo_reasoning_tradeoff_v1",
  maxAttempts: 60,
  cases: 20,
  libraryCases: 2,
  controlCases: 18,
  budgetNanoUsd: 10_000_000_000,
  seed: 20261002,
  deadlineMs: 90000,
  openaiBillingMultiplier: 1.1,
  minimumNetGain: 2,
  minimumLibraryGain: 1,
  maximumLatencyRatio: 0.8,
  method: "paired_discordant_clopper_pearson_bonferroni_v1",
  familyAlpha: 0.05,
  comparisons: 2,
  developmentOnly: true,
});
export const TRADEOFF_ARMS = ["low", "medium", "gemini"] as const;
export type TradeoffArm = typeof TRADEOFF_ARMS[number];
export type TradeoffCase = ScoringCase & { stratum: "library" | "control" };
const ORDERS: readonly (readonly TradeoffArm[])[] = [
  ["low", "medium", "gemini"],
  ["low", "gemini", "medium"],
  ["medium", "low", "gemini"],
  ["medium", "gemini", "low"],
  ["gemini", "low", "medium"],
  ["gemini", "medium", "low"],
];
export function tradeoffOrder(cases: readonly TradeoffCase[]) {
  check(cases.length === TRADEOFF.cases);
  const ordered = [...cases].sort((a, b) =>
    a.input.caseId.localeCompare(b.input.caseId)
  );
  const rng = random(TRADEOFF.seed);
  for (let i = ordered.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [ordered[i], ordered[j]] = [ordered[j], ordered[i]];
  }
  return ordered.flatMap((c, i) =>
    ORDERS[i < 18 ? i % ORDERS.length : i === 18 ? 0 : 3].map((arm) => ({
      c,
      arm,
    }))
  );
}

export async function prepareReasoningTradeoff(
  root: string,
  source: SourceIdentity,
) {
  const plan = fields(await readJson(join(root, "tradeoff-plan.json")), [
    "version",
    "mode",
    "authorizationRef",
    "paidServiceApproved",
    "budgetNanoUsd",
    "inputPermissions",
    "packetRootDigest",
    "retainUntil",
    "sourceDigest",
    "corpusDigest",
    "reviewDigest",
    "taxonomyDigest",
    "openaiPricingDigest",
    "geminiPricingDigest",
    "credentialDigests",
  ]);
  check(
    plan.version === TRADEOFF.version &&
      plan.budgetNanoUsd === TRADEOFF.budgetNanoUsd,
  );
  member(plan.mode, ["offline", "inspection", "live"]);
  check(
    JSON.stringify(plan.inputPermissions) ===
      JSON.stringify(["openai", "gemini_paid"]),
  );
  token(plan.authorizationRef);
  timestamp(plan.retainUntil);
  for (
    const k of [
      "packetRootDigest",
      "sourceDigest",
      "corpusDigest",
      "reviewDigest",
      "taxonomyDigest",
      "openaiPricingDigest",
      "geminiPricingDigest",
    ]
  ) hash(plan[k]);
  check(
    plan.packetRootDigest ===
        await fingerprintJson(await Deno.realPath(root)) &&
      plan.sourceDigest === source.digest,
  );
  const credentials = fields(plan.credentialDigests, ["openai", "gemini"]);
  if (plan.mode === "live") {
    check(plan.paidServiceApproved === true && !source.dirty);
    hash(credentials.openai);
    hash(credentials.gemini);
  } else {check(
      plan.paidServiceApproved === false && credentials.openai === null &&
        credentials.gemini === null,
    );}
  const corpus = fields(await readJson(join(root, "tradeoff-corpus.json")), [
    "version",
    "cases",
  ]);
  check(
    corpus.version === "photo_reasoning_tradeoff_corpus_v1" &&
      await fingerprintJson(corpus) === plan.corpusDigest,
  );
  const taxonomy = parseTaxonomy(await readJson(join(root, "taxonomy.json")));
  check(
    taxonomy.version === "evaluation_taxonomy_v2" &&
      await fingerprintJson(taxonomy) === plan.taxonomyDigest,
  );
  const review = fields(await readJson(join(root, "tradeoff-review.json")), [
    "version",
    "reviewerKind",
    "independentHumanValidation",
    "cases",
  ]);
  check(
    review.version === "photo_reasoning_tradeoff_review_v1" &&
      review.independentHumanValidation === false &&
      review.reviewerKind ===
        (plan.mode === "offline" ? "synthetic" : "assistant") &&
      await fingerprintJson(review) === plan.reviewDigest,
  );
  const reviews = array(review.cases, 20, 20).map((v) =>
    fields(v, [
      "caseId",
      "assetDigest",
      "referenceDigest",
      "status",
      "inputPermissions",
      "rightsApproved",
      "personalDataExcluded",
      "nearDuplicatesReviewed",
      "exposure",
      "reportedFailure",
      "visible",
      "limitation",
      "sources",
    ])
  );
  check(new Set(reviews.map((r) => r.caseId)).size === 20);
  const ids = new Set<string>(),
    assets = new Set<string>(),
    groups = new Set<string>();
  const cases = array(corpus.cases, 20, 20).map((raw) => {
    const c = fields(raw, [
      "input",
      "reference",
      "category",
      "taxaGroup",
      "stratum",
    ]);
    const input = parseEvaluationInput(c.input);
    check(
      input.split === "development" && input.inputGroup === "photos" &&
        input.assets.length === 1 &&
        input.assets[0].kind === "image" &&
        input.observationTexts.length === 0 && input.clips.length === 0 &&
        input.context.currentMonth === null &&
        input.context.deviceRegion === null,
    );
    check(
      !ids.has(input.caseId) && !assets.has(input.assets[0].sha256) &&
        !groups.has(input.groupId),
    );
    ids.add(input.caseId);
    assets.add(input.assets[0].sha256);
    groups.add(input.groupId);
    validateReference(c.reference, plan.mode === "offline");
    member(c.category, CONFIDENCE_PROTOCOL.categories);
    member(c.taxaGroup, [...CONFIDENCE_PROTOCOL.taxaGroups, "none"]);
    member(c.stratum, ["library", "control"]);
    const r = reviews.find((r) => r.caseId === input.caseId);
    check(
      r && r.status === "accepted" &&
        r.assetDigest === input.assets[0].sha256 &&
        r.rightsApproved === true && r.personalDataExcluded === true &&
        r.nearDuplicatesReviewed === true,
    );
    check(
      JSON.stringify(r.inputPermissions) ===
        JSON.stringify(plan.inputPermissions),
    );
    member(r.exposure, ["previously_exposed_development", "synthetic"]);
    check(
      r.exposure ===
        (plan.mode === "offline"
          ? "synthetic"
          : "previously_exposed_development"),
    );
    member(r.reportedFailure, [
      "confirmed_by_owner",
      "not_individually_confirmed",
      "not_applicable",
    ]);
    text(r.visible, 2000);
    text(r.limitation, 2000);
    array(r.sources, plan.mode === "offline" ? 0 : 1, 12).forEach((s) => {
      text(s, 2048);
      const url = new URL(s);
      check(
        url.protocol === "https:" && !url.username && !url.password &&
          !url.search && !url.hash,
      );
    });
    return { ...c, input } as TradeoffCase;
  });
  // The separately digested review owns the source-grounded provenance.
  for (const c of cases) {
    const r = reviews.find((r) => r.caseId === c.input.caseId)!;
    check(r.referenceDigest === await fingerprintJson(c.reference));
    for (const taxon of c.reference.acceptableTaxa) {
      check(
        taxonomy.taxa.some((t) =>
          t.taxon.id === taxon.id && t.taxon.rank === taxon.rank
        ),
      );
    }
    check(
      c.reference.subject !== "human" &&
        c.reference.subject !== "indeterminate",
    );
  }
  check(
    cases.filter((c) => c.stratum === "library").length === 2 &&
      cases.filter((c) => c.stratum === "control").length === 18,
  );
  if (plan.mode !== "offline") {
    const bytes = await Deno.readFile(
      new URL(
        "../../../../docs/research/identification/answerability-adjudication-2026-10-01.json",
        import.meta.url,
      ),
    );
    check(await fingerprintBytes(bytes) === FEATURE_ADJUDICATION_SHA256);
    const historical = JSON.parse(new TextDecoder().decode(bytes)) as {
      eligibleCaseIds: string[];
      cases: { caseId: string; assetSha256: string; reference: unknown }[];
    };
    const controls = cases.filter((c) => c.stratum === "control");
    check(
      await fingerprintJson(controls.map((c) => c.input.caseId).sort()) ===
        await fingerprintJson([...historical.eligibleCaseIds].sort()),
    );
    for (const c of controls) {
      const original = historical.cases.find((r) =>
        r.caseId === c.input.caseId
      )!;
      check(
        c.input.assets[0].sha256 === original.assetSha256 &&
          await fingerprintJson(c.reference) ===
            await fingerprintJson(original.reference),
      );
    }
  }
  const openaiPricing = parseEvaluationPricing(
    await readJson(join(root, "openai-pricing.json")),
  );
  const geminiPricing = parsePricing(
    await readJson(join(root, "gemini-pricing.json")),
  );
  check(
    openaiPricing.version === "evaluation_openai_pricing_v1" &&
      await fingerprintJson(openaiPricing) === plan.openaiPricingDigest &&
      await fingerprintJson(geminiPricing) === plan.geminiPricingDigest,
  );
  const op = openaiPricing.models.find((p) => p.model === "gpt-6-sol"),
    gp = geminiPricing.models.find((p) => p.model === "gemini-2.5-pro");
  check(
    op && op.maxInputTokens >= 1050000 && op.maxBillableOutputTokens >= 8192,
  );
  check(
    gp && gp.maxInputTokens >= 1048576 && gp.maxBillableOutputTokens >= 65536,
  );
  const assignments = [];
  for (const { c, arm } of tradeoffOrder(cases)) {
    const request = await prepareEvidence(root, c.input);
    const low = buildOpenAIPhotoReasoningRequest(
      request,
      openAIPhotoReasoningSnapshot(request, "low"),
    );
    const medium = buildOpenAIPhotoReasoningRequest(
      request,
      openAIPhotoReasoningSnapshot(request, "medium"),
    );
    check(
      await fingerprintJson(low) ===
        await fingerprintJson(
          buildOpenAIConfidenceRequest(
            request,
            openAIConfidenceSnapshot(request),
          ),
        ),
    );
    check(
      await fingerprintJson(low) ===
        await fingerprintJson({ ...medium, reasoning: { effort: "low" } }),
    );
    const snapshot = openAIPhotoReasoningSnapshot(
      request,
      arm === "medium" ? "medium" : "low",
    );
    check(
      snapshot.model === "gpt-6-sol" &&
        snapshot.timeoutMs === TRADEOFF.deadlineMs,
    );
    const gemini = arm === "gemini"
      ? await assignmentFor(c.input, request, "gemini_pro", 1, geminiPricing)
      : null;
    if (gemini) {
      check(
        gemini.model === "gemini-2.5-pro" &&
          gemini.prompt === "identify_vision_v1" &&
          gemini.timeoutMs === TRADEOFF.deadlineMs &&
          "temperature" in gemini.generation &&
          gemini.generation.temperature === 0.1 &&
          gemini.generation.seed === 42 &&
          gemini.generation.maxOutputTokens === 8192 &&
          gemini.generation.thinkingBudget === 5000,
      );
    }
    const reservedNanoUsd = Math.ceil(
      (gemini?.reservedUsd ??
        reserveCost(openaiPricing, "gpt-6-sol") *
          TRADEOFF.openaiBillingMultiplier) * 1e9,
    );
    check(
      Number.isSafeInteger(reservedNanoUsd) && reservedNanoUsd > 0 &&
        reservedNanoUsd <= TRADEOFF.budgetNanoUsd,
    );
    assignments.push({
      key: `${c.input.caseId}-${arm}`,
      caseId: c.input.caseId,
      arm,
      stratum: c.stratum,
      requestDigest: gemini?.requestDigest ??
        await fingerprintJson(arm === "medium" ? medium : low),
      settingsDigest: gemini?.policyDigest ?? await fingerprintJson(snapshot),
      reservedNanoUsd,
      gemini,
    });
  }
  const manifest = {
    version: "photo_reasoning_tradeoff_manifest_v1",
    protocol: TRADEOFF,
    source,
    planDigest: await fingerprintJson(plan),
    assignments,
  };
  const path = join(root, "tradeoff-manifest.json");
  if (await exists(path)) {
    check(
      await fingerprintJson(await readJson(path)) ===
        await fingerprintJson(manifest),
    );
  } else await claimJson(path, manifest);
  return {
    plan,
    cases,
    taxonomy,
    openaiPricing,
    geminiPricing,
    manifest,
    digest: await fingerprintJson(manifest),
  };
}
export type TradeoffStudy = Awaited<
  ReturnType<typeof prepareReasoningTradeoff>
>;
export type TradeoffAssignment =
  TradeoffStudy["manifest"]["assignments"][number];
