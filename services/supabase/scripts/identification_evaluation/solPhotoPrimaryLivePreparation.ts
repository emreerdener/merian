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
  buildSolPhotoPrimaryRequest,
  SOL_PRIMARY_PROFILE,
  solPhotoPrimarySnapshot,
} from "../../functions/_shared/ai/openaiSolPrimary.ts";
import { parseSolPrimaryPlan } from "./solPhotoPrimaryContracts.ts";
import {
  parsePrimaryPreparationPlan,
  parsePrimaryReferenceReview,
} from "./solPhotoPrimaryPreparationContracts.ts";
import { primaryReferenceCoverage } from "./solPhotoPrimaryCoverage.ts";
import { RUBRIC } from "./explanationContracts.ts";
import { requireCondition as check } from "./validation.ts";

export type SolPrimaryAssignment = Omit<PhotoModelAssignment, "profile"> & {
  profile: "openai_photo_sol_low_v1" | typeof SOL_PRIMARY_PROFILE;
  instructionsDigest: string;
  schemaDigest: string;
};
/** Only a billing/parser bridge: the recorded assignment digest remains the actual variant. */
export function primaryBillingAssignment(
  a: SolPrimaryAssignment,
): PhotoModelAssignment {
  check(a.model === "gpt-6-sol");
  return { ...a, profile: "openai_photo_sol_low_v1" };
}
export function solPrimaryRequest(
  request: Parameters<typeof solPhotoPrimarySnapshot>[0],
  candidate: boolean,
) {
  const snapshot = candidate
    ? solPhotoPrimarySnapshot(request)
    : openAIPhotoModelSnapshot(request, "openai_photo_sol_low_v1");
  const parameters = candidate
    ? buildSolPhotoPrimaryRequest(request, solPhotoPrimarySnapshot(request))
    : buildOpenAIPhotoModelRequestParameters(
      request,
      openAIPhotoModelSnapshot(request, "openai_photo_sol_low_v1"),
    );
  return { snapshot, parameters };
}
export async function loadSolPrimaryPacket(
  root: string,
  source: SourceIdentity,
  now = Date.now(),
) {
  const plan = parseSolPrimaryPlan(
    await readJson(join(root, "sol-primary-plan.json")),
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
    await readJson(join(root, "sol-primary-pricing.json")),
  );
  check(taxonomy.version === "evaluation_taxonomy_v2");
  const referenceReview = parsePrimaryReferenceReview(
    await readJson(join(root, "primary-reference-review.json")),
  );
  const preparationPlan = parsePrimaryPreparationPlan(
    await readJson(join(root, "primary-preparation-plan.json")),
  );
  const preparation = await readJson(
    join(root, "primary-preparation.json"),
  ) as Record<string, unknown>;
  check(plan.corpusDigest === await fingerprintRunCorpus(corpus));
  check(plan.taxonomyDigest === await fingerprintJson(taxonomy));
  check(plan.factsDigest === await fingerprintJson(facts));
  check(plan.pricingDigest === await fingerprintJson(pricing));
  check(plan.preparationDigest === await fingerprintJson(preparation));
  check(plan.referenceReviewDigest === await fingerprintJson(referenceReview));
  check(
    preparation.version === "sol_photo_primary_preparation_v1" &&
      preparation.profile === SOL_PRIMARY_PROFILE &&
      preparation.preparedCases === 12 &&
      preparation.proposedCalls === 18 &&
      preparation.dispatchAuthorized === false &&
      preparation.preparationPlanDigest ===
        await fingerprintJson(preparationPlan) &&
      preparation.referenceReviewDigest === plan.referenceReviewDigest &&
      preparation.rubricDigest === await fingerprintJson(RUBRIC) &&
      preparation.interpretationPolicy === plan.screeningPolicy,
  );
  check(
    preparationPlan.corpusDigest === plan.corpusDigest &&
      preparationPlan.taxonomyDigest === plan.taxonomyDigest &&
      preparationPlan.factsDigest === plan.factsDigest &&
      preparationPlan.referenceReviewDigest === plan.referenceReviewDigest &&
      await fingerprintJson(preparationPlan.screenCaseIds) ===
        await fingerprintJson(plan.screenCaseIds) &&
      await fingerprintJson(preparationPlan.challengeCaseIds) ===
        await fingerprintJson(plan.challengeCaseIds),
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
  const coverage = await primaryReferenceCoverage(
    corpus,
    taxonomy,
    facts,
    referenceReview,
  );
  check(coverage.missing.length === 0);
  check(
    await fingerprintJson(preparation.coverage) ===
      await fingerprintJson(coverage),
  );
  if (synthetic) check(plan.inputApproval === null);
  else {check(
      plan.inputApproval !== null && corpus.eligibility !== null &&
        now < Date.parse(corpus.eligibility.retainUntil),
    );}
  // Screens must exercise named organisms, biological abstention, a mineral,
  // and domestic dog/cat conventions before the paired visual challenges.
  const screened = (ids: string[]) =>
    ids.some((id) => plan.screenCaseIds.includes(id));
  check(
    screened(coverage.resolutions.species.caseIds) &&
      screened(coverage.resolutions.unresolved_biological.caseIds) &&
      screened(coverage.resolutions.non_biological.caseIds) &&
      screened(coverage.roles.domestic_dog.caseIds) &&
      screened(coverage.roles.domestic_cat.caseIds),
  );
  check(
    coverage.roles.species_lookalike.caseIds.some((id) =>
      plan.challengeCaseIds.includes(id)
    ),
  );
  const prepared = new Map<
    string,
    Omit<SolPrimaryAssignment, "ordinal" | "phase" | "attempt">[]
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
      const { snapshot, parameters } = solPrimaryRequest(request, candidate);
      variants.push({
        caseId: c.input.caseId,
        inputDigest,
        referenceDigest,
        factsDigest,
        profile: candidate
          ? SOL_PRIMARY_PROFILE
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
  const order: SolPrimaryAssignment[] = [];
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
    version: "sol_photo_primary_preflight_v1",
    dispatchAuthorized: false,
    liveControllerAvailable: true,
    source,
    planDigest: await fingerprintJson(plan),
    preparationDigest: plan.preparationDigest,
    referenceReviewDigest: plan.referenceReviewDigest,
    screeningPolicy: plan.screeningPolicy,
    recordVersion: "sol_primary_photo_attempt_v1",
    evidenceStatus: coverage.evidenceStatus,
    coverage,
    order,
    budgetUsd: plan.budgetUsd,
    regionalReservationUsd: reservedNanoUsd / 1e9,
    budgetFitsRegionalReservation:
      reservedNanoUsd <= Math.floor(plan.budgetUsd * 1e9),
  };
  return { plan, corpus, taxonomy, facts, pricing, referenceReview, report };
}
export type SolPrimaryPacket = Awaited<ReturnType<typeof loadSolPrimaryPacket>>;
export async function prepareSolPrimaryComparison(
  root: string,
  source: SourceIdentity,
) {
  await assertOfflinePermissions();
  const packet = await loadSolPrimaryPacket(root, source);
  await atomicJson(join(root, "sol-primary-preflight.json"), packet.report);
  return packet.report;
}
