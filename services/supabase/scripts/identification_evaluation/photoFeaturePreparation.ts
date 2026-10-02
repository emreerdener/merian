/** Offline preparation only. Historical packets are read-only inputs. */
import { dirname, join, relative, resolve } from "node:path";
import {
  buildOpenAIPhotoPrimaryRequest,
  openAIPhotoPrimarySnapshot,
} from "../../functions/_shared/ai/openaiPhotoPrimary.ts";
import { fileURLToPath } from "node:url";
import { prepareEvidence } from "./assets.ts";
import { parseConfidenceCorpus } from "./confidenceCorpus.ts";
import { validateConfidenceEvidence } from "./confidenceEvidence.ts";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import {
  claimJson,
  containedPath,
  privateDirectory,
  readBytes,
  sourceIdentity,
  syncDirectory,
} from "./files.ts";
import {
  buildPhotoFeatureRequest,
  photoFeatureSnapshot,
} from "./photoFeatureCandidate.ts";
import {
  parseTaxonomy,
  resolveTaxon,
  type ReviewedTaxonomy,
} from "./taxonomy.ts";
import type { ReferenceLabel } from "./contracts.ts";
import {
  array,
  fields,
  integer,
  requireCondition as check,
  text,
  token,
  validateReference,
} from "./validation.ts";

// This version is bound to reviewed bytes, not a caller-supplied answer key.
export const FEATURE_ADJUDICATION_SHA256 =
  "7374d11cf711b72894c978f3c1027475eec34a8b328cb5ccbe6aafafc1b7492c";

const record = (v: unknown): Record<string, unknown> => {
  check(!!v && typeof v === "object" && !Array.isArray(v));
  return v as Record<string, unknown>;
};
const digest = (v: unknown): string => {
  check(typeof v === "string" && /^[a-f0-9]{64}$/.test(v));
  return v as string;
};

/** Materialize only reviewed rows; a hold can never become a scored abstention. */
export function featureReferences(
  value: unknown,
  parent: ReturnType<typeof parseConfidenceCorpus>,
) {
  const v = record(value);
  check(v.version === "photo_answerability_adjudication_v1");
  check(v.referenceVersion === "photo-answerability-20261001-v1");
  check(
    v.independentHumanValidation === false && v.historicalRescoring === false,
  );
  const rows = array(v.cases, 20, 20).map(record);
  const ids = rows.map((r) => {
    token(r.caseId);
    return r.caseId as string;
  });
  check(new Set(ids).size === 20);
  const selected = array(v.eligibleCaseIds, 18, 18);
  const held = array(v.heldCaseIds, 2, 2);
  check(new Set(selected).size === 18 && new Set(held).size === 2);
  check(
    JSON.stringify([...held].sort()) === JSON.stringify(["c0005", "c0062"]),
  );
  check(selected.every((id) => ids.includes(String(id)) && !held.includes(id)));
  const overlay = record(v.taxonomyOverlay);
  check(
    overlay.parentTaxonomyByteSha256 ===
      record(v.sourceFileByteSha256)["taxonomy.json"],
  );
  check(array(overlay.editsToExistingEntries, 0, 0).length === 0);
  const additions = array(overlay.additions, 3, 3).map((raw) => {
    const a = record(raw);
    const verification = record(a.verification);
    check(
      verification.status === "ACCEPTED" && verification.matchType === "EXACT",
    );
    digest(verification.responseByteSha256);
    return {
      taxon: a.taxon,
      canonicalName: a.canonicalName,
      synonyms: a.synonyms,
    };
  });
  check(
    JSON.stringify(additions) === JSON.stringify([
      {
        taxon: { id: "gbif:6720", rank: "family" },
        canonicalName: "Apiaceae",
        synonyms: [],
      },
      {
        taxon: { id: "gbif:3685", rank: "family" },
        canonicalName: "Ardeidae",
        synonyms: [],
      },
      {
        taxon: { id: "gbif:9316", rank: "family" },
        canonicalName: "Laridae",
        synonyms: [],
      },
    ]),
  );
  const taxonomy = parseTaxonomy({
    ...parent.taxonomy,
    taxonomyVersion: overlay.taxonomyVersion,
    reviewRef: "answerability-adjudication-v1",
    taxa: [...parent.taxonomy.taxa, ...additions],
  }) as ReviewedTaxonomy;
  const cases = [];
  for (const row of rows) {
    const c = parent.corpus.cases.find((c) => c.input.caseId === row.caseId);
    check(c && c.input.inputGroup === "photos" && c.input.assets.length === 1);
    check(c.input.assets[0].sha256 === row.assetSha256);
    check(c.input.observationTexts.length === 0 && c.input.clips.length === 0);
    check(
      c.input.context.currentMonth === null &&
        c.input.context.deviceRegion === null,
    );
    if (held.includes(row.caseId)) {
      check(row.adjudicationStatus === "hold" && row.reference === null);
      continue;
    }
    check(
      selected.includes(row.caseId) && row.adjudicationStatus === "accepted",
    );
    validateReference(row.reference, false);
    const reference = row.reference as ReferenceLabel;
    for (const taxon of reference.acceptableTaxa) {
      const entry = taxonomy.taxa.find((t) => t.taxon.id === taxon.id);
      check(entry?.taxon.rank === taxon.rank);
      check(resolveTaxon(taxonomy, entry.canonicalName).taxon?.id === taxon.id);
    }
    for (const key of ["visible", "limitation", "rationale"]) {
      text(row[key], 2000);
    }
    for (const source of array(row.diagnosticSources, 0, 8)) {
      text(source, 2048);
      const url = new URL(source);
      check(url.protocol === "https:" && !url.username && !url.password);
    }
    array(row.parentEvidenceRefs, 0, 16).forEach(token);
    array(row.mechanisms, 0, 3).forEach((m) => integer(m, 1, 3));
    cases.push({
      input: { ...c.input, split: "development" as const },
      originalSplit: c.input.split,
      reference,
      category: c.category,
      taxaGroup: c.taxaGroup,
      parentCuration: c.curation,
      review: {
        visible: row.visible,
        limitation: row.limitation,
        rationale: row.rationale,
        diagnosticSources: row.diagnosticSources,
        parentEvidenceRefs: row.parentEvidenceRefs,
        mechanisms: row.mechanisms,
      },
    });
  }
  check(cases.length === 18);
  return { cases, taxonomy, heldCaseIds: held };
}

/**
 * Prepares a separate private packet without making the old runner accept it.
 * No live mode exists. Missing collector/reviewer/accounting integration remains
 * explicit; changing a manifest Boolean cannot authorize or enable execution.
 */
export async function preparePhotoFeatures(
  repository: string,
  parentRoot: string,
  adjudicationPath: string,
  outputRoot: string,
) {
  const moduleRoot = resolve(
    dirname(fileURLToPath(import.meta.url)),
    "../../../..",
  );
  check(await Deno.realPath(repository) === await Deno.realPath(moduleRoot));
  const canonicalRepository = await Deno.realPath(moduleRoot);
  const outsideRepository = (path: string) => {
    const rel = relative(canonicalRepository, path);
    check(rel === ".." || rel.startsWith("../"));
  };
  outsideRepository(await Deno.realPath(parentRoot));
  const bytes = await readBytes(adjudicationPath, 1024 * 1024);
  check(await fingerprintBytes(bytes) === FEATURE_ADJUDICATION_SHA256);
  const adjudication = record(
    JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
  );
  const audit = record(adjudication.parentAudit);
  check(audit.path === "answerability-review-2026-10-01.json");
  const auditBytes = await readBytes(
    join(dirname(adjudicationPath), audit.path),
    1024 * 1024,
  );
  check(await fingerprintBytes(auditBytes) === digest(audit.byteSha256));
  const parentAudit = JSON.parse(
    new TextDecoder("utf-8", { fatal: true }).decode(auditBytes),
  );
  const hashes = fields(adjudication.sourceFileByteSha256, [
    "confidence-corpus.json",
    "confidence-evidence.json",
    "taxonomy.json",
    "screen-manifest.json",
  ]);
  const bound = new Map<string, unknown>();
  for (const [name, hash] of Object.entries(hashes)) {
    const data = await readBytes(
      await containedPath(parentRoot, name),
      4 * 1024 * 1024,
    );
    check(await fingerprintBytes(data) === digest(hash));
    bound.set(
      name,
      JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(data)),
    );
  }
  const parent = parseConfidenceCorpus(
    bound.get("confidence-corpus.json"),
    bound.get("taxonomy.json"),
  );
  check(
    parent.corpus.kind === "reference" &&
      parent.corpus.referenceStatus === "valid",
  );
  const evidence = record(bound.get("confidence-evidence.json"));
  const parentEvidenceDigest = await validateConfidenceEvidence(
    evidence,
    parent.corpus,
  );
  const prepared = featureReferences(adjudication, parent);
  const records = array(evidence.records, 1, 2200).map(record);
  const used = new Set<string>();
  for (const c of prepared.cases) {
    const r = c.parentCuration;
    check(r.kind === "reviewed");
    [
      r.sourceRecordRef,
      r.referenceRecordRef,
      r.answerabilityRecordRef,
      ...r.independentEvidenceRefs,
    ].forEach((id) => used.add(id));
  }
  const parentEvidence = {
    version: "photo_feature_parent_evidence_subset_v1",
    historicalReferencesOnly: true,
    records: records.filter((r) => used.has(String(r.id))),
  };
  check(parentEvidence.records.length === used.size);
  const assignments = [];
  // Deterministic alternating order. This preparation does not claim randomization.
  for (const [index, c] of prepared.cases.entries()) {
    const request = await prepareEvidence(parentRoot, c.input);
    for (
      const arm of index % 2 ? ["features", "primary"] : ["primary", "features"]
    ) {
      const snapshot = arm === "features"
        ? photoFeatureSnapshot(request)
        : openAIPhotoPrimarySnapshot(request);
      const parameters = arm === "features"
        ? buildPhotoFeatureRequest(request, photoFeatureSnapshot(request))
        : buildOpenAIPhotoPrimaryRequest(
          request,
          openAIPhotoPrimarySnapshot(request),
        );
      assignments.push({
        ordinal: assignments.length + 1,
        caseId: c.input.caseId,
        arm,
        snapshotDigest: await fingerprintJson(snapshot),
        requestDigest: await fingerprintJson(parameters),
      });
    }
  }
  const source = await sourceIdentity(repository);
  const output = await privateDirectory(outputRoot);
  outsideRepository(output);
  // Refuse reuse, even for an apparently incomplete prior preparation.
  check([...Deno.readDirSync(output)].length === 0);
  await Deno.mkdir(join(output, "assets"), { mode: 0o700 });
  for (const c of prepared.cases) {
    const asset = c.input.assets[0];
    const data = await readBytes(
      await containedPath(parentRoot, asset.path),
      asset.byteLength,
    );
    check(await fingerprintBytes(data) === asset.sha256);
    // parseConfidenceCorpus fixes paths to assets/<asset-id>.<allowed-extension>.
    check(/^assets\/a[0-9]{4,12}\.(jpg|png|webp)$/.test(asset.path));
    using file = await Deno.open(join(output, asset.path), {
      write: true,
      createNew: true,
      mode: 0o600,
    });
    let offset = 0;
    while (offset < data.length) {
      const n = await file.write(data.subarray(offset));
      check(n > 0);
      offset += n;
    }
    await file.sync();
  }
  await syncDirectory(join(output, "assets"));
  const corpus = {
    version: "photo_feature_development_corpus_v1",
    referenceVersion: adjudication.referenceVersion,
    cases: prepared.cases,
  };
  await claimJson(join(output, "feature-corpus.json"), corpus);
  await claimJson(join(output, "taxonomy.json"), prepared.taxonomy);
  await claimJson(join(output, "adjudication.json"), adjudication);
  await claimJson(join(output, "parent-evidence.json"), parentEvidence);
  await claimJson(join(output, "parent-audit.json"), parentAudit);
  const manifest = {
    version: "photo_feature_offline_preparation_v1",
    source,
    paidServiceApproved: false,
    dispatchSupported: false,
    proposedCalls: 36,
    budgetNanoUsd: null,
    retainUntil: "2026-10-22T00:00:00.000Z",
    adjudicationByteDigest: await fingerprintBytes(bytes),
    parentEvidenceDigest,
    parentEvidenceSubsetDigest: await fingerprintJson(parentEvidence),
    corpusDigest: await fingerprintJson(corpus),
    taxonomyDigest: await fingerprintJson(prepared.taxonomy),
    assignments,
    heldCaseIds: prepared.heldCaseIds,
    readiness: {
      requestAndReferencePreparation: true,
      paidCollector: false,
      transientReviewIntegration: false,
      pricingAndAuthorization: false,
    },
  };
  await claimJson(join(output, "preparation.json"), manifest);
  return manifest;
}
