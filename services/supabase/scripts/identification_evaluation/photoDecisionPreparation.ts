import { validateDecisionExposure } from "./photoDecisionExposure.ts";
/** One bounded photo decision, reusing the existing corpus, builders and accounting. */
import { join } from "node:path";
import {
  buildOpenAIConfidenceRequest,
  openAIConfidenceSnapshot,
} from "../../functions/_shared/ai/openaiPhotoConfidence.ts";
import {
  buildOpenAIPhotoEvidenceRequest,
  openAIPhotoEvidenceSnapshot,
} from "../../functions/_shared/ai/openaiPhotoEvidence.ts";
import { prepareEvidence } from "./assets.ts";
import { parseConfidenceCorpus } from "./confidenceCorpus.ts";
import { confidenceEvidenceDigest } from "./confidenceEvidence.ts";
import { fingerprintJson } from "./evidence.ts";
import { claimJson, exists, readJson } from "./files.ts";
import { assignmentFor, random, reserveCost } from "./profiles.ts";
import {
  hash,
  parseEvaluationPricing,
  parsePricing,
  type SourceIdentity,
  timestamp,
} from "./runContracts.ts";
import {
  array,
  fields,
  requireCondition as check,
  token,
} from "./validation.ts";
import { PHOTO_DECISION_PROTOCOL as P } from "./photoDecisionStatistics.ts";

export type DecisionArm = "released" | "gemini" | "evidence";
export async function preparePhotoDecision(
  root: string,
  source: SourceIdentity,
) {
  const plan = fields(await readJson(join(root, "decision-plan.json")), [
    "version",
    "authorizationRef",
    "packetRootDigest",
    "retainUntil",
    "inputPermissions",
    "developmentIds",
    "validationIds",
    "reviewRef",
    "exposureReviewDigest",
  ]);
  check(plan.version === P.version);
  token(plan.authorizationRef);
  token(plan.reviewRef);
  hash(plan.packetRootDigest);
  hash(plan.exposureReviewDigest);
  timestamp(plan.retainUntil);
  check(
    plan.packetRootDigest === await fingerprintJson(await Deno.realPath(root)),
  );
  check(
    JSON.stringify(plan.inputPermissions) ===
      JSON.stringify(["openai", "gemini_paid"]),
  );
  const exposure = await readJson(join(root, "exposure-review.json"));
  check(await fingerprintJson(exposure) === plan.exposureReviewDigest);
  const { corpus, taxonomy } = parseConfidenceCorpus(
    await readJson(join(root, "confidence-corpus.json")),
    await readJson(join(root, "taxonomy.json")),
  );
  check(corpus.kind === "reference" && corpus.referenceStatus === "valid");
  const evidenceDigest = await confidenceEvidenceDigest(root, corpus);
  const ids = array(plan.developmentIds, 20, 20) as string[];
  ids.forEach(token);
  check(new Set(ids).size === 20);
  const development = ids.map((id) => {
    const c = corpus.cases.find((x) => x.input.caseId === id);
    check(c?.input.split === "development");
    return c;
  });
  const validationIds = array(plan.validationIds, 60, 60) as string[];
  validationIds.forEach(token);
  check(new Set(validationIds).size === 60);
  await validateDecisionExposure(exposure, corpus, ids, validationIds);
  const prior = fields(
    await readJson(join(root, "prior-exposure-evidence.json")),
    ["manifest", "claims", "inventory"],
  );
  const review = exposure as {
    priorJournalDigest: string;
    inventoryDigest: string;
  };
  check(
    review.priorJournalDigest ===
      await fingerprintJson({ manifest: prior.manifest, claims: prior.claims }),
  );
  check(review.inventoryDigest === await fingerprintJson(prior.inventory));
  const priorManifest = prior.manifest as {
    corpusDigest: string;
    assignments: { caseId: string; split: string; requestDigest: string }[];
  };
  check(priorManifest.corpusDigest === await fingerprintJson(corpus));
  const claims = array(prior.claims, 100, 100) as {
    manifestDigest: string;
    caseId: string;
    split: string;
    requestDigest: string;
  }[];
  const priorDigest = await fingerprintJson(prior.manifest);
  check(new Set(claims.map((c) => c.caseId)).size === 100);
  for (const claim of claims) {
    check(
      claim.manifestDigest === priorDigest && claim.split === "development" &&
        corpus.cases.some((c) =>
          c.input.caseId === claim.caseId && c.input.split === "development"
        ) && priorManifest.assignments.some((a) =>
          a.caseId === claim.caseId && a.requestDigest === claim.requestDigest
        ),
    );
  }
  check(
    ids.every((id) => claims.some((c) => c.caseId === id)) &&
      validationIds.every((id) => !claims.some((c) => c.caseId === id)),
  );

  const validation = validationIds.map((id) => {
    const c = corpus.cases.find((c) => c.input.caseId === id);
    check(c?.input.split === "held_out");
    return c;
  });
  for (
    const category of [
      "clear",
      "lookalike",
      "limited",
      "cultivated",
      "nonbiological",
    ]
  ) check(validation.filter((c) => c.category === category).length === 12);
  for (const category of ["clear", "lookalike", "limited"]) {
    for (const group of ["plant", "fungus", "invertebrate", "vertebrate"]) {
      check(
        validation.filter((c) =>
          c.category === category && c.taxaGroup === group
        ).length === 3,
      );
    }
  }
  check(
    validation.filter((c) =>
      c.category === "limited" && c.reference.supportedRank === "genus"
    ).length === 6,
  );
  for (const c of [...development, ...validation]) {
    check(
      c.input.assets.length === 1 && c.input.inputGroup === "photos" &&
        c.input.observationTexts.length === 0 &&
        c.input.context.deviceRegion === null &&
        c.input.context.currentMonth === null,
    );
  }
  const openaiPricing = parseEvaluationPricing(
    await readJson(join(root, "openai-pricing.json")),
  );
  check(openaiPricing.version === "evaluation_openai_pricing_v1");
  const geminiPricing = parsePricing(
    await readJson(join(root, "gemini-pricing.json")),
  );
  const op = openaiPricing.models.find((x) => x.model === "gpt-6-sol"),
    gp = geminiPricing.models.find((x) => x.model === "gemini-2.5-pro");
  check(
    op && op.maxInputTokens >= 1050000 && op.maxBillableOutputTokens >= 8192,
  );
  check(
    gp && gp.maxInputTokens >= 1048576 && gp.maxBillableOutputTokens >= 65536,
  );
  const rng = random(P.seed);
  const assignments = [];
  for (
    const [phase, cases, arms] of [["development", development, [
      "released",
      "evidence",
    ]], ["validation", validation, ["released", "gemini", "evidence"]]] as const
  ) {
    const ordered = [...cases].sort((a, b) =>
      a.input.caseId.localeCompare(b.input.caseId)
    );
    for (let i = ordered.length - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      [ordered[i], ordered[j]] = [ordered[j], ordered[i]];
    }
    for (const [index, c] of ordered.entries()) {
      const request = await prepareEvidence(root, c.input);
      const rotated = [
        ...arms.slice(index % arms.length),
        ...arms.slice(0, index % arms.length),
      ];
      for (const arm of rotated) {
        const gemini = arm === "gemini"
          ? await assignmentFor(
            c.input,
            request,
            "gemini_pro",
            1,
            geminiPricing,
          )
          : null;
        const snapshot = arm === "evidence"
          ? openAIPhotoEvidenceSnapshot(request)
          : openAIConfidenceSnapshot(request);
        const native = arm === "evidence"
          ? buildOpenAIPhotoEvidenceRequest(
            request,
            openAIPhotoEvidenceSnapshot(request),
          )
          : buildOpenAIConfidenceRequest(
            request,
            openAIConfidenceSnapshot(request),
          );
        const reservation = arm === "gemini"
          ? gemini!.reservedUsd
          : reserveCost(openaiPricing, "gpt-6-sol") * 1.1;
        assignments.push({
          key: `${phase}-${c.input.caseId}-${arm}`,
          phase,
          caseId: c.input.caseId,
          arm,
          requestDigest: gemini?.requestDigest ?? await fingerprintJson(native),
          settingsDigest: gemini?.policyDigest ??
            await fingerprintJson(snapshot),
          reservedNanoUsd: Math.ceil(reservation * 1e9),
          gemini,
        });
      }
    }
  }
  const manifest = {
    version: "photo_decision_manifest_v1",
    protocol: P,
    source,
    planDigest: await fingerprintJson(plan),
    corpusDigest: await fingerprintJson(corpus),
    taxonomyDigest: await fingerprintJson(taxonomy),
    evidenceDigest,
    openaiPricingDigest: await fingerprintJson(openaiPricing),
    geminiPricingDigest: await fingerprintJson(geminiPricing),
    assignments,
  };
  const path = join(root, "decision-manifest.json");
  if (await exists(path)) {
    check(
      await fingerprintJson(await readJson(path)) ===
        await fingerprintJson(manifest),
    );
  } else await claimJson(path, manifest);
  return {
    plan,
    corpus,
    taxonomy,
    development,
    validation,
    openaiPricing,
    geminiPricing,
    manifest,
    digest: await fingerprintJson(manifest),
  };
}
export type PhotoDecisionStudy = Awaited<
  ReturnType<typeof preparePhotoDecision>
>;
export type PhotoDecisionAssignment =
  PhotoDecisionStudy["manifest"]["assignments"][number];
