/** Offline copy and deterministic requests only. No approval or execution artifact. */
import { basename, dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  buildOpenAIPhotoModelRequestParameters,
  openAIPhotoModelSnapshot,
} from "../../functions/_shared/ai/openaiPhotoModels.ts";
import { assertOfflinePermissions } from "./admission.ts";
import { prepareEvidence, validateImage } from "./assets.ts";
import {
  fingerprintBytes,
  fingerprintEvidence,
  fingerprintJson,
} from "./evidence.ts";
import {
  claimJson,
  containedPath,
  exists,
  readBytes,
  readJson,
  syncDirectory,
} from "./files.ts";
import {
  parsePhotoModelFacts,
  parsePhotoModelPlan,
} from "./photoModelContracts.ts";
import { repairPhotoTaxonomy } from "./photoTaxonomyRepair.ts";
import {
  buildSolPhotoRankRequest,
  SOL_RANK_PROFILE,
  solPhotoRankSnapshot,
} from "./solPhotoRankCandidate.ts";
import { requireCondition as check } from "./validation.ts";

const repository = fileURLToPath(new URL("../../../../", import.meta.url));
const within = (parent: string, child: string) => {
  const rel = relative(parent, child);
  return rel === "" || (!rel.startsWith("../") && rel !== "..");
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
type ProposedAssignment = Omit<PreparedCase, "profiles"> & PreparedProfile & {
  ordinal: number;
  phase: "screen" | "challenge";
  attempt: 1;
};

/** The new receipt records preparation, not biological validation or permission. */
export async function prepareSolPhotoRankPacket(
  source: string,
  destination: string,
  remapValue: unknown,
) {
  await assertOfflinePermissions();
  const root = await Deno.realPath(source), target = resolve(destination);
  const parent = await Deno.realPath(dirname(target));
  check(root === resolve(source) && parent === dirname(target));
  check(!within(root, target) && !within(target, root));
  check(!await exists(target));
  check(!within(repository, target) && !within(repository, root));
  check(
    !await exists(join(root, ".git")) && !await exists(join(parent, ".git")),
  );
  const repair = await repairPhotoTaxonomy(
    await readJson(await containedPath(root, "corpus.json")),
    await readJson(
      await containedPath(root, "taxonomy.json"),
      32 * 1024 * 1024,
    ),
    remapValue,
  );
  const plan = parsePhotoModelPlan(
    await readJson(await containedPath(root, "photo-model-plan.json")),
  );
  const facts = parsePhotoModelFacts(
    await readJson(await containedPath(root, "photo-model-facts.json")),
  );
  check(
    plan.corpusDigest === repair.remap.sourceCorpusDigest &&
      plan.taxonomyDigest === repair.remap.sourceTaxonomyDigest &&
      plan.factsDigest === await fingerprintJson(facts),
  );
  const caseIds = [...plan.screenCaseIds, ...plan.challengeCaseIds];
  const { corpus, taxonomy } = repair;
  check(
    corpus.cases.length === 12 &&
      corpus.cases.every((c) => caseIds.includes(c.input.caseId)) &&
      facts.cards.every((c) => caseIds.includes(c.caseId)),
  );
  const prepared: PreparedCase[] = [];
  for (const c of corpus.cases) {
    check(
      c.input.inputGroup === "photos" &&
        c.input.observationTexts.length === 0 &&
        c.input.clips.length === 0 &&
        c.input.assets.every((a) => a.kind === "image"),
    );
    const card = facts.cards.find((f) => f.caseId === c.input.caseId)!;
    const inputDigest = await fingerprintEvidence(c.input);
    check(card.inputDigest === inputDigest);
    const reference = c.provisionalReference!;
    check(
      (reference.subject !== "biological" ||
        card.requirements.includes("rank_limit")) &&
        (reference.subject !== "non_biological" ||
          card.requirements.includes("non_biological_reason")) &&
        (reference.resolution !== "unresolved" ||
          card.requirements.includes("abstention_reason")),
    );
    const request = await prepareEvidence(root, c.input);
    const baselineSnapshot = openAIPhotoModelSnapshot(
      request,
      "openai_photo_sol_low_v1",
    );
    const candidateSnapshot = solPhotoRankSnapshot(request);
    const variants = [
      {
        snapshot: baselineSnapshot,
        parameters: buildOpenAIPhotoModelRequestParameters(
          request,
          baselineSnapshot,
        ),
      },
      {
        snapshot: candidateSnapshot,
        parameters: buildSolPhotoRankRequest(request, candidateSnapshot),
      },
    ];
    prepared.push({
      caseId: c.input.caseId,
      inputDigest,
      referenceDigest: await fingerprintJson(reference),
      factsDigest: await fingerprintJson(card),
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
  const order: ProposedAssignment[] = [];
  const append = (
    caseId: string,
    phase: "screen" | "challenge",
    candidate: boolean,
  ) => {
    const c = prepared.find((c) => c.caseId === caseId)!;
    const { profiles, ...evidence } = c;
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
  // The exclusive directory and receipt-last protocol never overwrite prior work.
  await Deno.mkdir(target, { mode: 0o700 });
  await syncDirectory(parent);
  await Deno.mkdir(join(target, "assets"), { mode: 0o700 });
  const seenPaths = new Set<string>();
  for (const c of corpus.cases) {
    for (const asset of c.input.assets) {
      check(!seenPaths.has(asset.path));
      seenPaths.add(asset.path);
      const bytes = await readBytes(
        await containedPath(root, asset.path),
        asset.byteLength,
      );
      check(
        bytes.length === asset.byteLength &&
          await fingerprintBytes(bytes) === asset.sha256,
      );
      validateImage(bytes, asset.mimeType);
      using file = await Deno.open(
        join(target, "assets", basename(asset.path)),
        {
          write: true,
          createNew: true,
          mode: 0o600,
        },
      );
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
      ["taxonomy-remap.json", repair.remap],
      ["taxonomy-repair.json", repair.report],
    ] as const
  ) await claimJson(join(target, name), value);

  // Revalidate the destination bytes before publishing its receipt.
  for (const c of corpus.cases) await prepareEvidence(target, c.input);
  const receipt = {
    version: "sol_photo_rank_preparation_v1" as const,
    dispatchAuthorized: false,
    liveControllerAvailable: false,
    readyForLive: false,
    referenceReviewComplete: false,
    referenceStatus: corpus.evidenceOrigin === "synthetic"
      ? "synthetic_mechanics_only"
      : "provisional_reused_development_cases",
    remainingWork: [
      "review_reference_and_finite_catalog_coverage",
      "version_live_plan_manifest_approval_and_v2_record_admission",
      "review_current_pricing_and_new_run_budget",
    ],
    profile: SOL_RANK_PROFILE,
    sourcePlanDigest: await fingerprintJson(plan),
    factsDigest: await fingerprintJson(facts),
    repair: repair.report,
    preparedCases: prepared.length,
    proposedCalls: order.length,
    order,
  };
  await claimJson(join(target, "sol-rank-preparation.json"), receipt);
  return receipt;
}
