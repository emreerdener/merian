/** Offline preflight for the separately versioned, fixed Sol comparison. */
import { join } from "node:path";
import {
  buildOpenAIPhotoModelRequestParameters,
  openAIPhotoModelSnapshot,
} from "../../functions/_shared/ai/openaiPhotoModels.ts";
import { assertOfflinePermissions } from "./admission.ts";
import { prepareEvidence } from "./assets.ts";
import {
  fingerprintBytes,
  fingerprintEvidence,
  fingerprintJson,
} from "./evidence.ts";
import { fingerprintRunCorpus, parseExploratoryCorpus } from "./exploratory.ts";
import { atomicJson, readJson } from "./files.ts";
import {
  parsePhotoModelFacts,
  parsePhotoModelPricing,
  photoModelReservationNanoUsd,
} from "./photoModelContracts.ts";
import type { PhotoModelAssignment } from "./photoModelPreparation.ts";
import { auditPhotoTaxonomy } from "./photoTaxonomyAudit.ts";
import { parseTaxonomy, type SourceIdentity } from "./runContracts.ts";
import {
  buildSolPhotoRankRequest,
  SOL_RANK_PROFILE,
  solPhotoRankSnapshot,
} from "./solPhotoRankCandidate.ts";
import {
  parseSolRankPlan,
  parseSolRankReferenceReview,
} from "./solPhotoRankContracts.ts";
import { requireCondition as check } from "./validation.ts";

export type SolRankAssignment = Omit<PhotoModelAssignment, "profile"> & {
  profile: "openai_photo_sol_low_v1" | typeof SOL_RANK_PROFILE;
  instructionsDigest: string;
  schemaDigest: string;
};
/** Only a billing/parser bridge: the recorded assignment digest remains the actual variant. */
export function solBillingAssignment(
  a: SolRankAssignment,
): PhotoModelAssignment {
  check(a.model === "gpt-6-sol");
  return { ...a, profile: "openai_photo_sol_low_v1" };
}
export function solRankRequest(
  request: Parameters<typeof solPhotoRankSnapshot>[0],
  candidate: boolean,
) {
  const snapshot = candidate
    ? solPhotoRankSnapshot(request)
    : openAIPhotoModelSnapshot(request, "openai_photo_sol_low_v1");
  const parameters = candidate
    ? buildSolPhotoRankRequest(request, solPhotoRankSnapshot(request))
    : buildOpenAIPhotoModelRequestParameters(
      request,
      openAIPhotoModelSnapshot(request, "openai_photo_sol_low_v1"),
    );
  return { snapshot, parameters };
}
export async function loadSolRankPacket(
  root: string,
  source: SourceIdentity,
  now = Date.now(),
) {
  const plan = parseSolRankPlan(
    await readJson(join(root, "sol-rank-plan.json")),
  );
  const corpus = parseExploratoryCorpus(
    await readJson(join(root, "corpus.json")),
  );
  const taxonomy = parseTaxonomy(
    await readJson(join(root, "taxonomy.json"), 32 * 1024 * 1024),
  );
  const facts = parsePhotoModelFacts(
    await readJson(join(root, "photo-model-facts.json")),
  );
  const pricing = parsePhotoModelPricing(
    await readJson(join(root, "sol-rank-pricing.json")),
  );
  const referenceReview = parseSolRankReferenceReview(
    await readJson(join(root, "sol-rank-reference-review.json")),
  );
  const preparation = await readJson(
    join(root, "sol-rank-preparation.json"),
  ) as Record<string, unknown>;
  check(plan.corpusDigest === await fingerprintRunCorpus(corpus));
  check(plan.taxonomyDigest === await fingerprintJson(taxonomy));
  check(plan.factsDigest === await fingerprintJson(facts));
  check(plan.pricingDigest === await fingerprintJson(pricing));
  check(plan.preparationDigest === await fingerprintJson(preparation));
  check(plan.referenceReviewDigest === await fingerprintJson(referenceReview));
  check(
    preparation.version === "sol_photo_rank_preparation_v1" &&
      preparation.profile === SOL_RANK_PROFILE &&
      preparation.preparedCases === 12 &&
      preparation.proposedCalls === 18 &&
      preparation.dispatchAuthorized === false &&
      preparation.factsDigest === plan.factsDigest,
  );
  const audit = await auditPhotoTaxonomy(corpus, taxonomy);
  check(audit.catalogConsistency === "clear");
  check(
    referenceReview.corpusDigest === plan.corpusDigest &&
      referenceReview.taxonomyDigest === plan.taxonomyDigest &&
      referenceReview.factsDigest === plan.factsDigest &&
      Date.parse(referenceReview.reviewedAt) <= now,
  );
  check(
    now >= Date.parse(pricing.retrievedAt) &&
      now - Date.parse(pricing.retrievedAt) <= 7 * 86400000,
  );
  const caseIds = [...plan.screenCaseIds, ...plan.challengeCaseIds];
  check(
    corpus.cases.length === 12 &&
      corpus.cases.every((c) => caseIds.includes(c.input.caseId)),
  );
  check(facts.cards.every((c) => caseIds.includes(c.caseId)));
  const synthetic = corpus.evidenceOrigin === "synthetic";
  check(
    referenceReview.referenceStatus ===
      (synthetic
        ? "synthetic_mechanics_only"
        : "provisional_reused_development_cases"),
  );
  if (synthetic) check(plan.inputApproval === null);
  else {check(
      plan.inputApproval !== null && corpus.eligibility !== null &&
        now < Date.parse(corpus.eligibility.retainUntil),
    );}
  const screens = corpus.cases.filter((c) =>
    plan.screenCaseIds.includes(c.input.caseId)
  );
  check(
    screens.filter((c) =>
          c.provisionalReference?.subject === "biological" &&
          c.provisionalReference.resolution === "named"
        ).length === 5 &&
      screens.filter((c) =>
          c.provisionalReference?.subject === "non_biological"
        ).length === 1,
  );
  const challenges = corpus.cases.filter((c) =>
    plan.challengeCaseIds.includes(c.input.caseId)
  );
  check(
    challenges.some((c) =>
      c.provisionalReference?.subject === "non_biological"
    ) &&
      challenges.some((c) =>
        c.provisionalReference?.subject === "biological" &&
        c.provisionalReference.supportedRank !== "species"
      ),
  );
  const prepared = new Map<
    string,
    Omit<SolRankAssignment, "ordinal" | "phase" | "attempt">[]
  >();
  for (const c of corpus.cases) {
    check(
      c.input.inputGroup === "photos" && c.input.clips.length === 0 &&
        c.input.observationTexts.length === 0 && c.input.assets.every((a) =>
          a.kind === "image"
        ),
    );
    const reference = c.provisionalReference;
    check(reference !== null);
    const card = facts.cards.find((f) => f.caseId === c.input.caseId)!;
    const reviewed = referenceReview.cases.find((r) =>
      r.caseId === c.input.caseId
    );
    const inputDigest = await fingerprintEvidence(c.input),
      referenceDigest = await fingerprintJson(reference),
      factsDigest = await fingerprintJson(card);
    check(
      card.inputDigest === inputDigest &&
        reviewed?.inputDigest === inputDigest &&
        reviewed.referenceDigest === referenceDigest &&
        reviewed.factsDigest === factsDigest,
    );
    check(
      (reference.subject !== "biological" ||
        card.requirements.includes("rank_limit")) &&
        (reference.subject !== "non_biological" ||
          card.requirements.includes("non_biological_reason")) &&
        (reference.resolution !== "unresolved" ||
          card.requirements.includes("abstention_reason")),
    );
    const request = await prepareEvidence(root, c.input);
    const variants = [];
    for (const candidate of [false, true]) {
      const { snapshot, parameters } = solRankRequest(request, candidate);
      variants.push({
        caseId: c.input.caseId,
        inputDigest,
        referenceDigest,
        factsDigest,
        profile: candidate
          ? SOL_RANK_PROFILE
          : "openai_photo_sol_low_v1" as const,
        model: snapshot.model,
        snapshotDigest: await fingerprintJson(snapshot),
        requestDigest: await fingerprintJson(parameters),
        instructionsDigest: await fingerprintBytes(
          new TextEncoder().encode(parameters.instructions),
        ),
        schemaDigest: await fingerprintJson(parameters.text.format),
        reservedNanoUsd: photoModelReservationNanoUsd(
          "openai_photo_sol_low_v1",
          pricing,
        ),
      });
    }
    prepared.set(c.input.caseId, variants);
  }
  const order: SolRankAssignment[] = [];
  const append = (
    caseId: string,
    phase: "screen" | "challenge",
    candidate: boolean,
  ) =>
    order.push({
      ordinal: order.length + 1,
      phase,
      attempt: 1,
      ...prepared.get(caseId)![candidate ? 1 : 0],
    });
  for (const id of plan.screenCaseIds) append(id, "screen", true);
  for (const [i, id] of plan.challengeCaseIds.entries()) {
    for (const candidate of i % 2 === 0 ? [true, false] : [false, true]) {
      append(id, "challenge", candidate);
    }
  }
  // The receipt's offline requests must match exactly; pricing is new and separate.
  check(
    await fingerprintJson(order.map(({ reservedNanoUsd: _, ...a }) => a)) ===
      await fingerprintJson(preparation.order),
  );
  const reservedNanoUsd = order.reduce(
    (n, a) => n + Math.ceil(a.reservedNanoUsd * 11 / 10),
    0,
  );
  const report = {
    version: "sol_photo_rank_preflight_v1",
    dispatchAuthorized: false,
    liveControllerAvailable: true,
    source,
    planDigest: await fingerprintJson(plan),
    preparationDigest: plan.preparationDigest,
    referenceReviewDigest: plan.referenceReviewDigest,
    screeningPolicy: plan.screeningPolicy,
    recordVersion: "photo_model_attempt_v2",
    evidenceStatus: referenceReview.referenceStatus,
    order,
    budgetUsd: plan.budgetUsd,
    regionalReservationUsd: reservedNanoUsd / 1e9,
    budgetFitsRegionalReservation:
      reservedNanoUsd <= Math.floor(plan.budgetUsd * 1e9),
  };
  return { plan, corpus, taxonomy, facts, pricing, referenceReview, report };
}
export type SolRankPacket = Awaited<ReturnType<typeof loadSolRankPacket>>;
export async function prepareSolRankComparison(
  root: string,
  source: SourceIdentity,
) {
  await assertOfflinePermissions();
  const packet = await loadSolRankPacket(root, source);
  await atomicJson(join(root, "sol-rank-preflight.json"), packet.report);
  return packet.report;
}
