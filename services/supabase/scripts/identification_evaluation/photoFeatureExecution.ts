/** Validated bridge from the offline packet into the bounded collector. */
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { prepareEvidence } from "./assets.ts";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import {
  containedPath,
  privateDirectory,
  readBytes,
  readJson,
  sourceIdentity,
} from "./files.ts";
import { FEATURE_ADJUDICATION_SHA256 } from "./photoFeaturePreparation.ts";
import {
  type FeatureRunInput,
  type FeatureRunPlan,
} from "./photoFeatureRun.ts";
import { parseTaxonomy, type ReviewedTaxonomy } from "./taxonomy.ts";
import { parseEvaluationPricing } from "./runContracts.ts";
import type { ReferenceLabel } from "./contracts.ts";
import {
  array,
  fields,
  parseEvaluationInput,
  requireCondition as check,
} from "./validation.ts";
const object = (value: unknown) => {
  check(value !== null && typeof value === "object" && !Array.isArray(value));
  return value as Record<string, unknown>;
};
export const featureRepository = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../..",
);
export async function loadFeatureExecution(
  packet: string,
  planPath: string,
): Promise<FeatureRunInput> {
  const root = await privateDirectory(packet),
    repo = await Deno.realPath(featureRepository);
  const rel = relative(repo, root);
  check(rel === ".." || rel.startsWith("../"));
  const load = (name: string) => readJson(join(root, name));
  const prep = object(await load("preparation.json"));
  check(
    prep.version === "photo_feature_offline_preparation_v1" &&
      prep.paidServiceApproved === false && prep.dispatchSupported === false &&
      prep.proposedCalls === 36,
  );
  const source = await sourceIdentity(repo);
  check(object(prep.source).digest === source.digest);
  const canonicalBytes = await readBytes(
    join(
      repo,
      "docs/research/identification/answerability-adjudication-2026-10-01.json",
    ),
    1024 * 1024,
  );
  check(await fingerprintBytes(canonicalBytes) === FEATURE_ADJUDICATION_SHA256);
  const adjudication = object(
    JSON.parse(new TextDecoder().decode(canonicalBytes)),
  );
  check(
    await fingerprintJson(await load("adjudication.json")) ===
      await fingerprintJson(adjudication),
  );
  const corpus = fields(await load("feature-corpus.json"), [
    "version",
    "referenceVersion",
    "cases",
  ]);
  check(
    corpus.version === "photo_feature_development_corpus_v1" &&
      corpus.referenceVersion === adjudication.referenceVersion,
  );
  check(await fingerprintJson(corpus) === prep.corpusDigest);
  const taxonomy = parseTaxonomy(
    await load("taxonomy.json"),
  ) as ReviewedTaxonomy;
  check(await fingerprintJson(taxonomy) === prep.taxonomyDigest);
  check(
    prep.taxonomyDigest ===
      "df0f1d6694cf22cb9db603b196f1dca24e841648f86901d840074a11bf155805",
  );
  const plan = fields(await readJson(planPath), [
    "mode",
    "paidServiceApproved",
    "authorizationRef",
    "budgetNanoUsd",
    "retainUntil",
    "sourceDigest",
    "packetDigest",
    "pricingDigest",
    "reviewSeed",
    "reviewerAssignments",
  ]) as unknown as FeatureRunPlan;
  check(
    plan.sourceDigest === source.digest &&
      plan.packetDigest === await fingerprintJson(prep),
  );
  check(plan.retainUntil === prep.retainUntil);
  const pricing = parseEvaluationPricing(await load("feature-pricing.json"));
  check("provider" in pricing && pricing.provider === "openai");
  check(await fingerprintJson(pricing) === plan.pricingDigest);
  const rows = array(adjudication.cases, 20, 20).map(object);
  const cases = [];
  for (const raw of array(corpus.cases, 18, 18)) {
    const c = object(raw), input = parseEvaluationInput(c.input);
    const reference = rows.find((r) => r.caseId === input.caseId);
    check(
      reference?.adjudicationStatus === "accepted" &&
        input.split === "development" && input.assets.length === 1 &&
        input.observationTexts.length === 0 &&
        input.context.deviceRegion === null &&
        input.context.currentMonth === null,
    );
    check(input.assets[0].sha256 === reference.assetSha256);
    check(
      await fingerprintJson(c.reference) ===
        await fingerprintJson(reference.reference),
    );
    check(
      await fingerprintJson(object(c.review).mechanisms) ===
        await fingerprintJson(reference.mechanisms),
    );
    const request = await prepareEvidence(root, input);
    // Recheck symlink containment and bytes through the original asset loader.
    await containedPath(root, input.assets[0].path);
    cases.push({
      caseId: input.caseId,
      reference: c.reference as ReferenceLabel,
      mechanisms: reference.mechanisms as number[],
      imageDigest: input.assets[0].sha256,
      reviewCard: [reference.visible as string],
      request,
    });
  }
  check(
    await fingerprintJson(cases.map((c) => c.caseId).sort()) ===
      await fingerprintJson(
        [...(adjudication.eligibleCaseIds as string[])].sort(),
      ),
  );
  return { plan, cases, taxonomy, pricing };
}
