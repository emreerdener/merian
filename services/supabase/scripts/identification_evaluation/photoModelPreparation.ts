/** Offline photo-model preparation. No credential, adapter, or dispatch import. */
import { join } from "node:path";
import {
  buildOpenAIPhotoModelRequestParameters,
  OPENAI_PHOTO_MODEL_PROFILES,
  type OpenAIPhotoModelProfile,
  openAIPhotoModelSnapshot,
} from "../../functions/_shared/ai/openaiPhotoModels.ts";
import { assertOfflinePermissions } from "./admission.ts";
import { prepareEvidence } from "./assets.ts";
import { fingerprintEvidence, fingerprintJson } from "./evidence.ts";
import {
  fingerprintRunCorpus,
  parseExploratoryCorpus,
  referenceLabels,
} from "./exploratory.ts";
import { atomicJson, readJson } from "./files.ts";
import {
  parsePhotoModelFacts,
  parsePhotoModelPlan,
  parsePhotoModelPricing,
  PHOTO_MODEL_TOKEN_CEILINGS,
  photoModelReservationNanoUsd,
} from "./photoModelContracts.ts";
import {
  parseTaxonomy,
  referenceTaxaExist,
  type SourceIdentity,
} from "./runContracts.ts";
import { requireCondition as check } from "./validation.ts";

interface PreparedProfile {
  profile: OpenAIPhotoModelProfile;
  model: string;
  snapshotDigest: string;
  requestDigest: string;
  reservedNanoUsd: number;
}
interface PreparedCase {
  caseId: string;
  inputDigest: string;
  referenceDigest: string;
  factsDigest: string;
  profiles: Map<OpenAIPhotoModelProfile, PreparedProfile>;
}
export type PhotoModelAssignment =
  & Omit<PreparedCase, "profiles">
  & PreparedProfile
  & {
    ordinal: number;
    phase: "screen" | "challenge";
    attempt: 1;
  };

export async function loadPhotoModelPacket(
  root: string,
  source: SourceIdentity,
  now = Date.now(),
) {
  const plan = parsePhotoModelPlan(
    await readJson(join(root, "photo-model-plan.json")),
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
    await readJson(join(root, "photo-model-pricing.json")),
  );
  check(plan.corpusDigest === await fingerprintRunCorpus(corpus));
  check(plan.taxonomyDigest === await fingerprintJson(taxonomy));
  check(plan.factsDigest === await fingerprintJson(facts));
  check(plan.pricingDigest === await fingerprintJson(pricing));
  check(corpus.taxonomyVersion === taxonomy.taxonomyVersion);
  check(
    referenceTaxaExist(
      taxonomy,
      referenceLabels(corpus).flatMap((r) => [...r.acceptableTaxa]),
    ),
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
  const screenReferences = corpus.cases.filter((c) =>
    plan.screenCaseIds.includes(c.input.caseId)
  ).map((c) => c.provisionalReference);
  check(
    screenReferences.filter((r) =>
          r?.subject === "biological" && r.resolution === "named"
        ).length === 5 &&
      screenReferences.filter((r) => r?.subject === "non_biological").length ===
        1,
    "invalid_reference",
  );
  const challengeReferences = corpus.cases.filter((c) =>
    plan.challengeCaseIds.includes(c.input.caseId)
  ).map((c) => c.provisionalReference);
  check(
    challengeReferences.some((r) => r?.subject === "non_biological") &&
      challengeReferences.some((r) =>
        r?.subject === "biological" &&
        (r.resolution === "unresolved" || r.supportedRank !== "species")
      ),
    "invalid_reference",
  );
  const synthetic = corpus.evidenceOrigin === "synthetic";
  if (synthetic) check(plan.inputApproval === null);
  else {
    check(plan.inputApproval !== null, "unapproved_evidence");
    check(
      corpus.eligibility !== null &&
        now < Date.parse(corpus.eligibility.retainUntil),
      "unapproved_evidence",
    );
  }
  const prepared = new Map<string, PreparedCase>();
  for (const c of corpus.cases) {
    check(
      c.input.inputGroup === "photos" && c.input.clips.length === 0 &&
        c.input.assets.every((a) => a.kind === "image"),
      "invalid_media",
    );
    // This comparison intentionally reuses the no-description photo benchmark.
    check(c.input.observationTexts.length === 0, "invalid_media");
    check(c.provisionalReference !== null, "invalid_reference");
    const card = facts.cards.find((f) => f.caseId === c.input.caseId)!;
    check(card.inputDigest === await fingerprintEvidence(c.input));
    const reference = c.provisionalReference;
    if (reference.resolution === "unresolved") {
      check(card.requirements.includes("abstention_reason"));
    }
    if (reference.subject === "non_biological") {
      check(card.requirements.includes("non_biological_reason"));
    }
    if (reference.subject === "biological") {
      check(card.requirements.includes("rank_limit"));
    }
    const request = await prepareEvidence(root, c.input);
    const profiles = new Map<OpenAIPhotoModelProfile, PreparedProfile>();
    for (const profile of OPENAI_PHOTO_MODEL_PROFILES) {
      const snapshot = openAIPhotoModelSnapshot(request, profile);
      const parameters = buildOpenAIPhotoModelRequestParameters(
        request,
        snapshot,
      );
      profiles.set(profile, {
        profile,
        model: snapshot.model,
        snapshotDigest: await fingerprintJson(snapshot),
        requestDigest: await fingerprintJson(parameters),
        reservedNanoUsd: photoModelReservationNanoUsd(profile, pricing),
      });
    }
    prepared.set(c.input.caseId, {
      caseId: c.input.caseId,
      inputDigest: card.inputDigest,
      referenceDigest: await fingerprintJson(reference),
      factsDigest: await fingerprintJson(card),
      profiles,
    });
  }
  const order: PhotoModelAssignment[] = [];
  const append = (
    caseId: string,
    phase: "screen" | "challenge",
    profile: OpenAIPhotoModelProfile,
  ) => {
    const c = prepared.get(caseId)!;
    order.push({
      ordinal: order.length + 1,
      phase,
      caseId,
      inputDigest: c.inputDigest,
      referenceDigest: c.referenceDigest,
      factsDigest: c.factsDigest,
      ...c.profiles.get(profile)!,
      attempt: 1,
    });
  };
  const [luna, sol] = OPENAI_PHOTO_MODEL_PROFILES;
  for (const caseId of plan.screenCaseIds) append(caseId, "screen", luna);
  for (const [index, caseId] of plan.challengeCaseIds.entries()) {
    for (const profile of index % 2 === 0 ? [luna, sol] : [sol, luna]) {
      append(caseId, "challenge", profile);
    }
  }
  const reservedNanoUsd = order.reduce((n, a) => n + a.reservedNanoUsd, 0);
  const report = {
    version: "photo_model_preflight_v1",
    dispatchAuthorized: false,
    liveControllerAvailable: true,
    evidenceStatus: synthetic
      ? "synthetic_mechanics_only"
      : "provisional_reference_pilot",
    preparedAt: new Date(now).toISOString(),
    source,
    planDigest: await fingerprintJson(plan),
    corpusDigest: plan.corpusDigest,
    taxonomyDigest: plan.taxonomyDigest,
    factsDigest: plan.factsDigest,
    pricingDigest: plan.pricingDigest,
    plannedCalls: order.length,
    attemptsPerAssignment: plan.attemptsPerAssignment,
    budgetUsd: plan.budgetUsd,
    tokenCeilings: PHOTO_MODEL_TOKEN_CEILINGS,
    fullScheduleReservationUsd: reservedNanoUsd / 1e9,
    fullScheduleReservationWithPremiumUsd:
      order.reduce((n, a) => n + Math.ceil(a.reservedNanoUsd * 11 / 10), 0) /
      1e9,
    budgetFitsRegionalReservation:
      order.reduce((n, a) => n + Math.ceil(a.reservedNanoUsd * 11 / 10), 0) <=
        Math.floor(plan.budgetUsd * 1e9),
    budgetFitsConservativeReservation:
      reservedNanoUsd <= Math.floor(plan.budgetUsd * 1e9),
    screenReviewRequiredBeforeChallenge: true,
    order,
  };
  return { report, plan, corpus, taxonomy, facts, pricing };
}

export type PhotoModelPacket = Awaited<ReturnType<typeof loadPhotoModelPacket>>;

/** A successful preflight never grants execution or reads credentials. */
export async function preparePhotoModelComparison(
  root: string,
  source: SourceIdentity,
  now = Date.now(),
) {
  await assertOfflinePermissions();
  const { report } = await loadPhotoModelPacket(root, source, now);
  await atomicJson(join(root, "photo-model-preflight.json"), report);
  return report;
}
