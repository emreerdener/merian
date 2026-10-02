/** Bounded collector + delayed blind review. Provider drafts never enter files. */
import { dirname, join } from "node:path";
import type {
  AIProviderOutcome,
  MultimodalAIRequest,
} from "../../functions/_shared/ai/contracts.ts";
import {
  buildOpenAIPhotoPrimaryRequest,
  openAIPhotoPrimarySnapshot,
} from "../../functions/_shared/ai/openaiPhotoPrimary.ts";
import {
  buildPhotoFeatureRequest,
  decodePhotoFeatureDraft,
  type PhotoFeature,
  photoFeatureSnapshot,
} from "./photoFeatureCandidate.ts";
import {
  confidenceAccounting,
  confidenceCost,
  parseConfidenceAccounting,
} from "./confidenceAccounting.ts";
import { parseConfidenceObservation } from "./confidenceScoring.ts";
import { projectDevelopmentDraft } from "./developmentProjection.ts";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import {
  atomicJson,
  claimJson,
  exists,
  privateDirectory,
  readJson,
  withRunLock,
} from "./files.ts";
import {
  type FeatureReviewer,
  parseFeatureReviewReceipt,
  reviewFeatureView,
  validateFeatureReviewers,
} from "./photoFeatureInstrument.ts";
import {
  type FeatureScoringCase,
  scorePhotoFeatures,
} from "./photoFeatureScoring.ts";
import { random, reserveCost } from "./profiles.ts";
import { parseEvaluationPricing } from "./runContracts.ts";
import type { OpenAIPricing } from "./runContracts.ts";
import { parseTaxonomy, type ReviewedTaxonomy } from "./taxonomy.ts";
import {
  array,
  fields,
  integer,
  requireCondition as check,
  text,
  token,
} from "./validation.ts";

export type FeatureArm = "primary" | "features";
export interface FeatureRunCase extends FeatureScoringCase {
  imageDigest: string;
  reviewCard: string[];
  request: MultimodalAIRequest;
}
export interface FeatureRunPlan {
  mode: "offline" | "live";
  paidServiceApproved: boolean;
  authorizationRef: string;
  budgetNanoUsd: number;
  retainUntil: string;
  sourceDigest: string;
  packetDigest: string;
  pricingDigest: string;
  reviewSeed: number;
  reviewerAssignments: { id: string; method: FeatureReviewer["method"] }[];
}
export interface FeatureRunInput {
  plan: FeatureRunPlan;
  cases: FeatureRunCase[];
  taxonomy: ReviewedTaxonomy;
  pricing: OpenAIPricing;
}
export interface FeatureProvider {
  mode: "offline" | "live";
  preflight: () => Promise<void>;
  invoke: (
    arm: FeatureArm,
    request: MultimodalAIRequest,
  ) => Promise<AIProviderOutcome>;
}
const filename = (n: number) => String(n).padStart(2, "0");
const cost = (
  accounting: ReturnType<typeof confidenceAccounting>,
  pricing: OpenAIPricing,
) => {
  const n = confidenceCost(accounting, pricing);
  return n === null ? null : Math.ceil(n * 1.1);
};
export function featureNative(request: MultimodalAIRequest, arm: FeatureArm) {
  return arm === "features"
    ? {
      snapshot: photoFeatureSnapshot(request),
      parameters: buildPhotoFeatureRequest(
        request,
        photoFeatureSnapshot(request),
      ),
    }
    : {
      snapshot: openAIPhotoPrimarySnapshot(request),
      parameters: buildOpenAIPhotoPrimaryRequest(
        request,
        openAIPhotoPrimarySnapshot(request),
      ),
    };
}
export async function freezeFeatureRun(root: string, input: FeatureRunInput) {
  const { plan, cases } = input;
  check(plan.mode === "offline" || plan.mode === "live");
  check(plan.paidServiceApproved === (plan.mode === "live"));
  token(plan.authorizationRef);
  integer(plan.budgetNanoUsd, 1, 100_000_000_000);
  integer(plan.reviewSeed, 0, 0xffffffff);
  check(Number.isFinite(Date.parse(plan.retainUntil)));
  for (const h of [plan.sourceDigest, plan.packetDigest, plan.pricingDigest]) {
    check(/^[a-f0-9]{64}$/.test(h));
  }
  check(
    plan.reviewerAssignments.length === 2 &&
      plan.reviewerAssignments[0].id !== plan.reviewerAssignments[1].id,
  );
  plan.reviewerAssignments.forEach((r) => {
    check(r.id === "slot-01" || r.id === "slot-02");
    check(
      ["local_interactive", ...(plan.mode === "offline" ? ["synthetic"] : [])]
        .includes(r.method),
    );
  });
  // Validate scheduled reference/ID/mechanism shape even before any results exist.
  scorePhotoFeatures(cases, []);
  const taxonomy = parseTaxonomy(input.taxonomy) as ReviewedTaxonomy;
  const pricing = parseEvaluationPricing(input.pricing);
  check("provider" in pricing && pricing.provider === "openai");
  check(await fingerprintJson(pricing) === plan.pricingDigest);
  const reservedNanoUsd = Math.ceil(
    reserveCost(pricing, "gpt-6-sol") * 1e9 * 1.1,
  );
  integer(reservedNanoUsd, 1, plan.budgetNanoUsd);

  const assignments = [];
  for (const [i, c] of cases.entries()) {
    check(/^[a-f0-9]{64}$/.test(c.imageDigest));
    array(c.reviewCard, 1, 8).forEach((v) => text(v));
    const images = c.request.evidence.filter((e) => e.kind === "image");
    check(
      images.length === 1 &&
        !c.request.evidence.some((e) => e.kind === "audio"),
    );
    check(
      await fingerprintBytes(
        Uint8Array.from(atob(images[0].data), (c) => c.charCodeAt(0)),
      ) === c.imageDigest,
    );
    for (
      const arm of (i % 2
        ? ["features", "primary"]
        : ["primary", "features"]) as FeatureArm[]
    ) {
      const native = featureNative(c.request, arm);
      assignments.push({
        ordinal: assignments.length + 1,
        caseId: c.caseId,
        arm,
        imageDigest: c.imageDigest,
        requestDigest: await fingerprintJson(native.parameters),
        snapshotDigest: await fingerprintJson(native.snapshot),
        reservedNanoUsd,
      });
    }
  }
  const order = [...cases.map((c) => c.caseId)];
  const rng = random(plan.reviewSeed);
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  const directory = await privateDirectory(root);
  const stable = {
    version: "photo_feature_run_v1",
    plan,
    rootDigest: await fingerprintJson(directory),
    caseDigest: await fingerprintJson(
      cases.map(({ request: _request, ...c }) => c),
    ),
    taxonomyDigest: await fingerprintJson(taxonomy),
    pricingDigest: await fingerprintJson(pricing),
    assignments,
    reviewOrder: order,
  };
  const path = join(directory, "feature-run.json");
  const stableDigest = await fingerprintJson(stable);
  const tokens = cases.map((c) => ({
    caseId: c.caseId,
    token: crypto.randomUUID(),
  }));
  if (!await exists(path)) {
    await claimJson(path, { stable, stableDigest, tokens });
  }
  const saved = fields(await readJson(path), [
    "stable",
    "stableDigest",
    "tokens",
  ]);
  check(
    saved.stableDigest === stableDigest &&
      await fingerprintJson(saved.stable) === stableDigest,
  );
  const bindings = saved.tokens as typeof tokens;
  check(Array.isArray(bindings) && bindings.length === 18);
  bindings.forEach((b) => {
    fields(b, ["caseId", "token"]);
    token(b.token);
    check(cases.some((c) => c.caseId === b.caseId));
  });
  check(
    new Set(bindings.map((b) => b.caseId)).size === 18 &&
      new Set(bindings.map((b) => b.token)).size === 18,
  );
  return {
    root: directory,
    input: structuredClone(input),
    manifest: { ...stable, tokens: bindings },
    digest: await fingerprintJson(saved),
  };
}
type Study = Awaited<ReturnType<typeof freezeFeatureRun>>;
const claim = (study: Study, a: Study["manifest"]["assignments"][number]) => ({
  version: "photo_feature_claim_v1",
  runDigest: study.digest,
  assignment: a,
});

export async function featureRunReport(study: Study) {
  const allowed = new Set([
    ".lock",
    "feature-run.json",
    "feature-report.json",
    ...study.manifest.assignments.flatMap((a) =>
      ["claim", "result", "review", "review-claim"].map((kind) =>
        `${filename(a.ordinal)}.${kind}.json`
      )
    ),
  ]);
  for await (const e of Deno.readDir(study.root)) {
    check(e.isFile && !e.isSymlink && allowed.has(e.name));
  }
  const results = [];
  let attempted = 0, settledNanoUsd = 0, outstandingNanoUsd = 0;
  let stop: string | null = null;
  for (const a of study.manifest.assignments) {
    const base = join(study.root, filename(a.ordinal));
    if (!await exists(base + ".claim.json")) {
      check(!await exists(base + ".result.json"));
      continue;
    }
    check(a.ordinal === attempted + 1 && stop === null);
    const expected = claim(study, a);
    check(
      await fingerprintJson(await readJson(base + ".claim.json")) ===
        await fingerprintJson(expected),
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
      "accounting",
      "settledNanoUsd",
      "featureDigest",
      "featureCount",
      "featureBindingDigest",
      "durationMs",
    ]);
    check(
      r.version === "photo_feature_result_v1" &&
        r.claimDigest === await fingerprintJson(expected),
    );
    const observation = parseConfidenceObservation(r.observation);
    check(observation.prediction.caseId === a.caseId);
    const accounting = parseConfidenceAccounting(r.accounting),
      settled = cost(accounting, study.input.pricing);
    check(r.settledNanoUsd === settled);
    if (settled === null) {
      outstandingNanoUsd += a.reservedNanoUsd;
      stop = "accounting_incomplete";
    } else {
      integer(settled, 0, a.reservedNanoUsd);
      settledNanoUsd += settled;
    }
    check(
      typeof r.durationMs === "number" && Number.isFinite(r.durationMs) &&
        r.durationMs >= 0 && r.durationMs <= 600000,
    );
    check(
      r.featureDigest === null ||
        (a.arm === "features" && typeof r.featureDigest === "string" &&
          /^[a-f0-9]{64}$/.test(r.featureDigest)),
    );
    if (r.featureDigest === null) {
      check(r.featureCount === null && r.featureBindingDigest === null);
    } else {
      integer(r.featureCount, 0, 3);
      check(
        typeof r.featureBindingDigest === "string" &&
          /^[a-f0-9]{64}$/.test(r.featureBindingDigest),
      );
    }
    let review = null;
    const reviewPath = base + ".review.json";
    if (await exists(reviewPath)) {
      check(
        await fingerprintJson(await readJson(base + ".review-claim.json")) ===
          await fingerprintJson({
            runDigest: study.digest,
            resultDigest: await fingerprintJson(r),
          }),
      );
      const v = fields(await readJson(reviewPath), [
        "version",
        "resultDigest",
        "receipt",
      ]);
      check(
        v.version === "photo_feature_review_record_v1" &&
          v.resultDigest === await fingerprintJson(r),
      );
      review = parseFeatureReviewReceipt(v.receipt);
      check(review.verdicts[0].length === r.featureCount);
      check(
        await fingerprintJson({
          featureDigest: review.featureDigest,
          traits: review.traits,
        }) === r.featureBindingDigest,
      );
      check(
        review.cardDigest ===
          await fingerprintJson(
            study.input.cases.find((c) => c.caseId === a.caseId)!.reviewCard,
          ),
      );
      check(
        a.arm === "features" && review.imageDigest === a.imageDigest &&
          review.featureDigest === r.featureDigest,
      );
      check(
        review.token ===
          study.manifest.tokens.find((t) => t.caseId === a.caseId)?.token,
      );
      check(
        await fingerprintJson(review.reviewers) ===
          await fingerprintJson(study.input.plan.reviewerAssignments),
      );
    }
    results.push({ arm: a.arm, observation, review });
  }
  check(settledNanoUsd + outstandingNanoUsd <= study.input.plan.budgetNanoUsd);
  const next = study.manifest.assignments[attempted];
  if (
    next &&
    settledNanoUsd + outstandingNanoUsd + next.reservedNanoUsd >
      study.input.plan.budgetNanoUsd
  ) stop ??= "budget_exhausted";
  const scores = scorePhotoFeatures(study.input.cases, results);
  const complete = attempted === 36 && stop === null &&
    results.filter((r) => r.arm === "features").every((r) => r.review !== null);
  const report = {
    version: "photo_feature_run_report_v1",
    runDigest: study.digest,
    mode: study.input.plan.mode,
    attempted,
    settledNanoUsd,
    outstandingNanoUsd,
    stop: stop ?? (attempted === 36 && !complete ? "review_incomplete" : null),
    complete,
    scores,
    screenPassed: complete && scores.outcomeHurdleMet,
    productionActivation: false,
    confidenceQualification: false,
  };
  await atomicJson(join(study.root, "feature-report.json"), report);
  return report;
}

/** Read-only approval gate. Only an explicitly authorized operator issues this file. */
export async function verifyFeatureApproval(study: Study) {
  check(await exists(join(dirname(study.root), ".photo-feature-approvals")));
  const approvalDirectory = await privateDirectory(
    join(dirname(study.root), ".photo-feature-approvals"),
  );
  const path = join(
    approvalDirectory,
    await fingerprintJson(study.input.plan.authorizationRef) + ".json",
  );
  const approved = fields(await readJson(path), [
    "version",
    "authorizationRef",
    "runDigest",
    "rootDigest",
    "pricingDigest",
    "budgetNanoUsd",
    "maxCalls",
    "expiresAt",
  ]);
  check(
    approved.version === "photo_feature_user_approval_v1" &&
      approved.authorizationRef === study.input.plan.authorizationRef &&
      approved.runDigest === study.digest &&
      approved.rootDigest === study.manifest.rootDigest &&
      approved.pricingDigest === study.input.plan.pricingDigest &&
      approved.budgetNanoUsd === study.input.plan.budgetNanoUsd &&
      approved.maxCalls === 36 &&
      approved.expiresAt === study.input.plan.retainUntil &&
      Date.now() < Date.parse(String(approved.expiresAt)),
  );
}

/** One process owns collection and randomized review. An interrupted run never replays. */
export async function collectPhotoFeatures(
  root: string,
  input: FeatureRunInput,
  provider: FeatureProvider,
  reviewers: readonly FeatureReviewer[],
) {
  input = structuredClone(input);
  return await withRunLock(root, async () => {
    validateFeatureReviewers(reviewers);
    check(provider.mode === input.plan.mode);
    check(
      await fingerprintJson(
        reviewers.map(({ id, method }) => ({ id, method })),
      ) === await fingerprintJson(input.plan.reviewerAssignments),
    );
    const study = await freezeFeatureRun(root, input);
    const before = await featureRunReport(study);
    check(before.attempted === 0);
    if (input.plan.mode === "live") {
      await verifyFeatureApproval(study);
      check(Date.now() < Date.parse(input.plan.retainUntil));
      const age = Date.now() - Date.parse(input.pricing.retrievedAt);
      check(age >= 0 && age <= 7 * 86400000);
      const ledger = await privateDirectory(
        join(dirname(study.root), ".photo-feature-authorizations"),
      );
      const path = join(
        ledger,
        await fingerprintJson(input.plan.authorizationRef) + ".json",
      );
      const receipt = {
        rootDigest: study.manifest.rootDigest,
        runDigest: study.digest,
      };
      if (!await exists(path)) await claimJson(path, receipt);
      check(
        await fingerprintJson(await readJson(path)) ===
          await fingerprintJson(receipt),
      );
    }
    await provider.preflight();
    const pending = new Map<string, PhotoFeature[]>();
    let spent = 0;
    for (const a of study.manifest.assignments) {
      if (spent + a.reservedNanoUsd > study.input.plan.budgetNanoUsd) {
        return await featureRunReport(study);
      }
      if (input.plan.mode === "live") {
        check(Date.now() < Date.parse(input.plan.retainUntil));
      }
      const c = study.input.cases.find((c) => c.caseId === a.caseId)!;
      const base = join(study.root, filename(a.ordinal)),
        claimed = claim(study, a);
      check(
        await fingerprintJson(featureNative(c.request, a.arm).parameters) ===
            a.requestDigest &&
          await fingerprintJson(featureNative(c.request, a.arm).snapshot) ===
            a.snapshotDigest,
      );
      await claimJson(base + ".claim.json", claimed);
      let outcome: AIProviderOutcome;
      try {
        outcome = await provider.invoke(a.arm, structuredClone(c.request));
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
      let observation = parseConfidenceObservation({
        prediction: {
          caseId: a.caseId,
          outcome: outcome.kind === "draft" ? "invalid_output" : outcome.kind,
        },
        mapping: null,
      });
      let featureDigest: string | null = null;
      let featureCount: number | null = null;
      let featureBindingDigest: string | null = null;
      if (
        outcome.kind === "draft" &&
        outcome.mediaSafety?.disposition === "allowed" &&
        outcome.returnedModel === "gpt-6-sol" &&
        outcome.serviceTier === "default"
      ) {
        try {
          const decoded = a.arm === "features"
            ? decodePhotoFeatureDraft(outcome.draft)
            : { identification: outcome.draft, features: null };
          observation = projectDevelopmentDraft(
            a.caseId,
            "explicit_primary",
            decoded.identification,
            study.input.taxonomy,
          ).observation;
          if (
            decoded.features && observation.prediction.outcome === "normalized"
          ) {
            pending.set(a.caseId, decoded.features);
            featureDigest = await fingerprintJson(decoded.features);
            featureCount = decoded.features.length;
            featureBindingDigest = await fingerprintJson({
              featureDigest,
              traits: decoded.features.map(({ kind, visibility }) => ({
                kind,
                visibility,
              })),
            });
          }
        } catch { /* Bounded invalid_output, never raw parser errors. */ }
      }
      const accounting = confidenceAccounting(outcome),
        settledNanoUsd = cost(accounting, study.input.pricing);
      // An over-reservation response leaves its durable claim unsettled.
      if (settledNanoUsd !== null) {
        integer(settledNanoUsd, 0, a.reservedNanoUsd);
      }
      await claimJson(base + ".result.json", {
        version: "photo_feature_result_v1",
        claimDigest: await fingerprintJson(claimed),
        observation,
        accounting,
        settledNanoUsd,
        featureDigest,
        featureCount,
        featureBindingDigest,
        durationMs: outcome.providerDurationMs,
      });
      if (settledNanoUsd === null) return await featureRunReport(study);
      spent += settledNanoUsd;
    }
    // No outcome/reference joins are exposed to reviewers. Random order is frozen.
    for (const id of study.manifest.reviewOrder) {
      const features = pending.get(id);
      if (!features) continue;
      const a = study.manifest.assignments.find((a) =>
        a.caseId === id && a.arm === "features"
      )!;
      const c = study.input.cases.find((c) => c.caseId === id)!;
      const image = c.request.evidence.find((e) => e.kind === "image");
      check(image);
      const base = join(study.root, filename(a.ordinal));
      const resultDigest = await fingerprintJson(
        await readJson(base + ".result.json"),
      );
      await claimJson(base + ".review-claim.json", {
        runDigest: study.digest,
        resultDigest,
      });
      try {
        const receipt = await reviewFeatureView({
          token: study.manifest.tokens.find((t) => t.caseId === id)!.token,
          facts: c.reviewCard,
          image: {
            sha256: c.imageDigest,
            mimeType: image.mimeType,
            data: image.data,
          },
          features,
        }, reviewers);
        await claimJson(base + ".review.json", {
          version: "photo_feature_review_record_v1",
          resultDigest,
          receipt,
        });
      } catch {
        return await featureRunReport(study);
      } finally {
        pending.delete(id);
      }
    }
    return await featureRunReport(study);
  });
}
