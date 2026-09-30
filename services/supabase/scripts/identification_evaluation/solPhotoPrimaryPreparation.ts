/** Offline-only, immutable packet copy. No historical execution authority is read. */
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  buildOpenAIPhotoModelRequestParameters,
  openAIPhotoModelSnapshot,
} from "../../functions/_shared/ai/openaiPhotoModels.ts";
import {
  buildSolPhotoPrimaryRequest,
  SOL_PRIMARY_PROFILE,
  solPhotoPrimarySnapshot,
} from "../../functions/_shared/ai/openaiSolPrimary.ts";
import { assertOfflinePermissions } from "./admission.ts";
import { prepareEvidence, validateImage } from "./assets.ts";
import {
  fingerprintBytes,
  fingerprintEvidence,
  fingerprintJson,
} from "./evidence.ts";
import { RUBRIC } from "./explanationContracts.ts";
import { parseExploratoryCorpus } from "./exploratory.ts";
import {
  claimJson,
  containedPath,
  exists,
  readBytes,
  readJson,
  syncDirectory,
} from "./files.ts";
import { parsePhotoModelFacts } from "./photoModelContracts.ts";
import { auditPhotoTaxonomy } from "./photoTaxonomyAudit.ts";
import { primaryReferenceCoverage } from "./solPhotoPrimaryCoverage.ts";
import {
  parsePrimaryPreparationPlan,
  parsePrimaryReferenceReview,
} from "./solPhotoPrimaryPreparationContracts.ts";
import { parseTaxonomy } from "./taxonomy.ts";
import { requireCondition as check } from "./validation.ts";

const repository = fileURLToPath(new URL("../../../../", import.meta.url));
const within = (parent: string, child: string) => {
  const rel = relative(parent, child);
  return rel === "" || (rel !== ".." && !rel.startsWith("../"));
};
interface PreparedProfile {
  profile: string;
  model: string;
  snapshotDigest: string;
  requestDigest: string;
  instructionsDigest: string;
  schemaDigest: string;
}
interface PreparedCase {
  caseId: string;
  inputDigest: string;
  referenceDigest: string;
  factsDigest: string;
  profiles: PreparedProfile[];
}

export async function prepareSolPhotoPrimaryPacket(
  source: string,
  destination: string,
) {
  await assertOfflinePermissions();
  const root = await Deno.realPath(source), target = resolve(destination);
  const parent = await Deno.realPath(dirname(target));
  check(root === resolve(source) && parent === dirname(target));
  check(
    !within(root, target) && !within(target, root) && !await exists(target),
  );
  check(!within(repository, root) && !within(repository, target));
  check(
    !await exists(join(root, ".git")) && !await exists(join(parent, ".git")),
  );
  for (const path of [root, parent]) {
    const stat = await Deno.stat(path);
    check(stat.isDirectory && stat.mode !== null && (stat.mode & 0o077) === 0);
  }
  const load = async (name: string, limit?: number) =>
    await readJson(await containedPath(root, name), limit);
  const corpus = parseExploratoryCorpus(await load("corpus.json"));
  const taxonomy = parseTaxonomy(await load("taxonomy.json", 32 * 1024 * 1024));
  check(taxonomy.version === "evaluation_taxonomy_v2");
  const facts = parsePhotoModelFacts(await load("photo-model-facts.json"));
  const review = parsePrimaryReferenceReview(
    await load("primary-reference-review.json"),
  );
  const plan = parsePrimaryPreparationPlan(
    await load("primary-preparation-plan.json"),
  );
  check(
    plan.corpusDigest === await fingerprintJson(corpus) &&
      plan.taxonomyDigest === await fingerprintJson(taxonomy) &&
      plan.factsDigest === await fingerprintJson(facts) &&
      plan.referenceReviewDigest === await fingerprintJson(review),
  );
  const caseIds = [...plan.screenCaseIds, ...plan.challengeCaseIds];
  check(
    corpus.cases.length === 12 &&
      corpus.cases.every((c) => caseIds.includes(c.input.caseId)),
  );
  const catalogAudit = await auditPhotoTaxonomy(corpus, taxonomy);
  check(catalogAudit.catalogConsistency === "clear");
  const coverage = await primaryReferenceCoverage(
    corpus,
    taxonomy,
    facts,
    review,
  );
  const prepared: PreparedCase[] = [];
  for (const c of corpus.cases) {
    const request = await prepareEvidence(root, c.input);
    const baseline = openAIPhotoModelSnapshot(
      request,
      "openai_photo_sol_low_v1",
    );
    const candidate = solPhotoPrimarySnapshot(request);
    const variants = [
      {
        snapshot: baseline,
        parameters: buildOpenAIPhotoModelRequestParameters(request, baseline),
      },
      {
        snapshot: candidate,
        parameters: buildSolPhotoPrimaryRequest(request, candidate),
      },
    ];
    prepared.push({
      caseId: c.input.caseId,
      inputDigest: await fingerprintEvidence(c.input),
      referenceDigest: await fingerprintJson(c.provisionalReference),
      factsDigest: await fingerprintJson(
        facts.cards.find((f) => f.caseId === c.input.caseId),
      ),
      profiles: await Promise.all(
        variants.map(async ({ snapshot, parameters }) => ({
          profile: snapshot.profile,
          model: snapshot.model,
          snapshotDigest: await fingerprintJson(snapshot),
          requestDigest: await fingerprintJson(parameters),
          instructionsDigest: await fingerprintBytes(
            new TextEncoder().encode(parameters.instructions),
          ),
          schemaDigest: await fingerprintJson(parameters.text.format),
        })),
      ),
    });
  }
  const order: (Omit<PreparedCase, "profiles"> & PreparedProfile & {
    ordinal: number;
    phase: "screen" | "challenge";
    attempt: 1;
  })[] = [];
  const append = (
    caseId: string,
    phase: "screen" | "challenge",
    candidate: boolean,
  ) => {
    const { profiles, ...evidence } = prepared.find((c) =>
      c.caseId === caseId
    )!;
    order.push({
      ordinal: order.length + 1,
      phase,
      attempt: 1,
      ...evidence,
      ...profiles[candidate ? 1 : 0],
    });
  };
  for (const id of plan.screenCaseIds) append(id, "screen", true);
  for (const [index, id] of plan.challengeCaseIds.entries()) {
    for (const candidate of index % 2 === 0 ? [true, false] : [false, true]) {
      append(id, "challenge", candidate);
    }
  }
  // Validate everything before claiming a destination. A partial copy never gets a receipt.
  await Deno.mkdir(target, { mode: 0o700 });
  await syncDirectory(parent);
  await Deno.mkdir(join(target, "assets"), { mode: 0o700 });
  const seen = new Set<string>();
  for (const c of corpus.cases) {
    for (const asset of c.input.assets) {
      check(!seen.has(asset.path));
      seen.add(asset.path);
      const bytes = await readBytes(
        await containedPath(root, asset.path),
        asset.byteLength,
      );
      check(
        bytes.length === asset.byteLength &&
          await fingerprintBytes(bytes) === asset.sha256,
      );
      validateImage(bytes, asset.mimeType);
      using file = await Deno.open(join(target, asset.path), {
        write: true,
        createNew: true,
        mode: 0o600,
      });
      let offset = 0;
      while (offset < bytes.length) {
        const written = await file.write(bytes.subarray(offset));
        check(written > 0);
        offset += written;
      }
      await file.sync();
    }
  }
  await syncDirectory(join(target, "assets"));
  for (
    const [name, value] of [
      ["corpus.json", corpus],
      ["taxonomy.json", taxonomy],
      ["photo-model-facts.json", facts],
      ["primary-reference-review.json", review],
      ["primary-preparation-plan.json", plan],
    ] as const
  ) await claimJson(join(target, name), value);
  for (const c of corpus.cases) await prepareEvidence(target, c.input);
  const receipt = {
    version: "sol_photo_primary_preparation_v1" as const,
    profile: SOL_PRIMARY_PROFILE,
    dispatchAuthorized: false,
    readyForLive: false,
    liveControllerAvailable: false,
    referenceReviewBound: true,
    qualityQualified: false,
    preparationPlanDigest: await fingerprintJson(plan),
    referenceReviewDigest: plan.referenceReviewDigest,
    rubricDigest: await fingerprintJson(RUBRIC),
    interpretationPolicy: "primary_reference_limits_v1",
    remainingWork: [
      ...(coverage.missing.length ? ["fill_missing_reference_cases"] : []),
      ...(coverage.limitedOnly.length
        ? ["retain_unassessable_reference_limits"]
        : []),
      "implement_separate_live_decoder_and_durable_admission",
      "review_current_pricing_and_new_bounded_execution_authorization",
    ],
    catalogAudit,
    coverage,
    preparedCases: prepared.length,
    proposedCalls: order.length,
    prepared,
    order,
  };
  await claimJson(join(target, "primary-preparation.json"), receipt);
  return receipt;
}
