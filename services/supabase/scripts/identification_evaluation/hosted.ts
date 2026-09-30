/** Public test transport; private credentials/readiness never enter the bundle. */
import { decodeBase64, encodeBase64 } from "@std/encoding-base64";
import { dirname, join } from "node:path";
import { assertOfflinePermissions } from "./admission.ts";
import { prepareEvidence, validateImage } from "./assets.ts";
import {
  fingerprintBytes,
  fingerprintEvidence,
  fingerprintJson,
} from "./evidence.ts";
import { prepareExperiment } from "./experiment.ts";
import {
  EXPERIMENT_METRICS,
  parseExperimentPlan,
} from "./experimentContracts.ts";
import { saveExperimentReport } from "./experimentReport.ts";
import {
  type ExploratoryCorpus,
  parseExploratoryCorpus,
} from "./exploratory.ts";
import {
  atomicJson,
  claimJson,
  containedPath,
  exists,
  privateDirectory,
  readBytes,
  readJson,
} from "./files.ts";
import { reusableAssignmentFor, reusableProfile } from "./reusableProfiles.ts";
import { reserveCost } from "./profiles.ts";
import {
  type EvaluationPricing,
  type EvaluationReadiness,
  hash,
  number,
  parseEvaluationPricing,
  parseEvaluationReadiness,
  parseTaxonomy,
  type SourceIdentity,
  timestamp,
} from "./runContracts.ts";
import {
  array,
  fields,
  integer,
  requireCondition as check,
  text,
} from "./validation.ts";

export const HOSTED_PREFIX = "benchmarks/identification";
export const BUNDLE_LIMIT = 24 * 1024 * 1024;
export const PROVIDERS = ["gemini", "openai"] as const;
export type HostedProvider = typeof PROVIDERS[number];
export const HOSTED_RUNS = ["gemini-baseline", "openai-baseline"] as const;
export const HOSTED_PROFILES = [
  "gemini_photo_text_v1",
  "openai_photo_text_v1",
] as const;
const assetPath = /^assets\/a[0-9]{4}\.(png|jpg|jpeg|webp)$/;
function safeId(v: unknown): asserts v is string {
  check(typeof v === "string" && /^[a-z0-9][a-z0-9-]{0,63}$/.test(v));
}

export interface HostedReview {
  reviewRef: string;
  reviewedAt: string;
  expiresAt: string;
  paidServiceApproved: true;
  inputPermissionApproved: true;
  dedicatedEvaluationProject: boolean;
  termsRef: string;
  dataUseRef: string;
  regionSubprocessorRef: string;
  retentionAbuseLogRef: string;
}
export interface HostedSpec {
  version: "hosted_identification_spec_v1";
  experimentId: string;
  source: SourceIdentity;
  corpusDigest: string;
  taxonomyDigest: string;
  orderSeed: number;
  window: { startsAt: string; expiresAt: string };
  budgetUsd: number;
  publicRelease: { approved: true; reviewRef: string; attribution: string };
  runs: {
    provider: HostedProvider;
    profileDigest: string;
    budgetUsd: number;
    pricing: EvaluationPricing;
    review: HostedReview;
  }[];
}
export interface HostedBundle {
  version: "hosted_identification_bundle_v1";
  spec: HostedSpec;
  corpus: ExploratoryCorpus;
  taxonomy: ReturnType<typeof parseTaxonomy>;
  assets: { path: string; base64: string }[];
}

export function parseHostedSpec(value: unknown): HostedSpec {
  const v = fields(value, [
    "version",
    "experimentId",
    "source",
    "corpusDigest",
    "taxonomyDigest",
    "orderSeed",
    "window",
    "budgetUsd",
    "publicRelease",
    "runs",
  ]);
  check(v.version === "hosted_identification_spec_v1");
  safeId(v.experimentId);
  hash(v.corpusDigest);
  hash(v.taxonomyDigest);
  integer(v.orderSeed, 0, 0xffffffff);
  number(v.budgetUsd, 0.000000001, 100);
  const s = fields(v.source, ["commit", "dirty", "digest", "sdk"]);
  check(
    typeof s.commit === "string" && /^[a-f0-9]{40}$/.test(s.commit) &&
      s.dirty === false,
  );
  hash(s.digest);
  check(
    s.sdk === "npm:@google/genai@2.23.0" ||
      s.sdk === "npm:@google/genai@2.24.0",
  );
  const w = fields(v.window, ["startsAt", "expiresAt"]);
  timestamp(w.startsAt);
  timestamp(w.expiresAt);
  check(
    Date.parse(w.expiresAt as string) > Date.parse(w.startsAt as string) &&
      Date.parse(w.expiresAt as string) - Date.parse(w.startsAt as string) <=
        2 * 3600000,
  );
  const p = fields(v.publicRelease, ["approved", "reviewRef", "attribution"]);
  check(p.approved === true);
  safeId(p.reviewRef);
  text(p.attribution, 12000);
  let total = 0;
  array(v.runs, 2, 2).forEach((raw, i) => {
    const r = fields(raw, [
      "provider",
      "profileDigest",
      "budgetUsd",
      "pricing",
      "review",
    ]);
    check(r.provider === PROVIDERS[i]);
    hash(r.profileDigest);
    number(r.budgetUsd, 0.000000001, 100);
    total += r.budgetUsd as number;
    const pricing = parseEvaluationPricing(r.pricing);
    check((pricing.version === "evaluation_openai_pricing_v1") === (i === 1));
    const review = fields(r.review, [
      "reviewRef",
      "reviewedAt",
      "expiresAt",
      "paidServiceApproved",
      "inputPermissionApproved",
      "dedicatedEvaluationProject",
      "termsRef",
      "dataUseRef",
      "regionSubprocessorRef",
      "retentionAbuseLogRef",
    ]);
    for (
      const k of [
        "reviewRef",
        "termsRef",
        "dataUseRef",
        "regionSubprocessorRef",
        "retentionAbuseLogRef",
      ]
    ) safeId(review[k]);
    timestamp(review.reviewedAt);
    timestamp(review.expiresAt);
    check(
      review.paidServiceApproved === true &&
        review.inputPermissionApproved === true &&
        typeof review.dedicatedEvaluationProject === "boolean",
    );
    check(
      Date.parse(review.reviewedAt as string) <=
          Date.parse(w.startsAt as string) &&
        Date.parse(review.expiresAt as string) >=
          Date.parse(w.expiresAt as string),
    );
  });
  check(total <= (v.budgetUsd as number));
  return structuredClone(v) as unknown as HostedSpec;
}

/** Whole-bundle hash is checked before parsing. No URLs or archive paths are trusted. */
export async function validateHostedBundle(
  value: unknown,
): Promise<HostedBundle> {
  const v = fields(value, ["version", "spec", "corpus", "taxonomy", "assets"]);
  check(v.version === "hosted_identification_bundle_v1");
  const spec = parseHostedSpec(v.spec),
    corpus = parseExploratoryCorpus(v.corpus),
    taxonomy = parseTaxonomy(v.taxonomy);
  check(
    corpus.evidenceOrigin === "real" && corpus.eligibility !== null &&
      taxonomy.version === "evaluation_taxonomy_v2",
  );
  check(
    corpus.cases.length === 8 &&
      corpus.cases.filter((c) => c.input.inputGroup === "photos").length ===
        6 &&
      corpus.cases.filter((c) => c.input.inputGroup === "description")
          .length === 2,
  );
  check(
    Date.parse(corpus.eligibility.retainUntil) >=
      Date.parse(spec.window.expiresAt),
  );
  check(
    await fingerprintJson(corpus) === spec.corpusDigest &&
      await fingerprintJson(taxonomy) === spec.taxonomyDigest,
  );
  for (let i = 0; i < 2; i++) {
    check(
      (await reusableProfile(HOSTED_PROFILES[i])).digest ===
        spec.runs[i].profileDigest,
    );
  }
  const expected = corpus.cases.flatMap((c) => {
    check(
      Object.keys(c.input.context).every((k) =>
        ["currentMonth", "deviceRegion"].includes(k)
      ),
    );
    check(
      c.input.clips.length === 0 &&
        c.input.assets.length === (c.input.inputGroup === "photos" ? 1 : 0),
    );
    return c.input.assets;
  });
  const assets = array(v.assets, 6, 6).map((raw) => {
    const a = fields(raw, ["path", "base64"]);
    check(typeof a.path === "string" && assetPath.test(a.path));
    check(
      typeof a.base64 === "string" && a.base64.length <= 8 * 1024 * 1024 &&
        /^[A-Za-z0-9+/]+={0,2}$/.test(a.base64),
    );
    return { path: a.path, base64: a.base64 };
  });
  check(new Set(assets.map((a) => a.path)).size === 6);
  for (const a of assets) {
    const metadata = expected.find((e) => e.path === a.path);
    check(metadata && metadata.kind === "image");
    const bytes = decodeBase64(a.base64);
    check(
      bytes.length === metadata.byteLength &&
        await fingerprintBytes(bytes) === metadata.sha256,
    );
    validateImage(bytes, metadata.mimeType);
  }
  return {
    version: "hosted_identification_bundle_v1",
    spec,
    corpus,
    taxonomy,
    assets,
  };
}

export async function decodeHostedBundle(bytes: Uint8Array, digest: string) {
  hash(digest);
  check(
    bytes.length > 0 && bytes.length <= BUNDLE_LIMIT &&
      await fingerprintBytes(bytes) === digest,
  );
  return await validateHostedBundle(
    JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
  );
}

export async function exportHostedBundle(
  root: string,
  specPath: string,
  output: string,
) {
  await assertOfflinePermissions();
  const spec = parseHostedSpec(await readJson(specPath));
  const corpus = parseExploratoryCorpus(
    await readJson(join(root, "corpus.json")),
  );
  const taxonomy = parseTaxonomy(
    await readJson(join(root, "taxonomy.json"), 32 * 1024 * 1024),
  );
  const assets = [];
  for (const asset of corpus.cases.flatMap((c) => c.input.assets)) {
    check(assetPath.test(asset.path));
    assets.push({
      path: asset.path,
      base64: encodeBase64(
        await readBytes(await containedPath(root, asset.path), 6 * 1024 * 1024),
      ),
    });
  }
  const bundle = await validateHostedBundle({
    version: "hosted_identification_bundle_v1",
    spec,
    corpus,
    taxonomy,
    assets,
  });
  await claimJson(output, bundle);
  const bytes = await readBytes(output, BUNDLE_LIMIT);
  return {
    sha256: await fingerprintBytes(bytes),
    bytes: bytes.length,
    maxCalls: 16,
    budgetUsd: spec.budgetUsd,
  };
}

export async function stageHostedBundle(
  root: string,
  bytes: Uint8Array,
  digest: string,
  source: SourceIdentity,
) {
  check(!await exists(root));
  const bundle = await decodeHostedBundle(bytes, digest);
  check(
    await fingerprintJson(bundle.spec.source) === await fingerprintJson(source),
  );
  await privateDirectory(root);
  await privateDirectory(join(root, "assets"));
  for (const a of bundle.assets) {
    await Deno.writeFile(join(root, a.path), decodeBase64(a.base64), {
      createNew: true,
      mode: 0o600,
    });
  }
  await claimJson(join(root, "corpus.json"), bundle.corpus);
  await claimJson(join(root, "taxonomy.json"), bundle.taxonomy);
  await claimJson(join(root, "hosted-spec.json"), bundle.spec);
  await claimJson(join(root, "bundle-binding.json"), { digest });
  await privateDirectory(join(root, "approvals"));
}

export async function hostedReadiness(
  spec: HostedSpec,
  corpus: ExploratoryCorpus,
  provider: HostedProvider,
  credential: string,
): Promise<EvaluationReadiness> {
  const i = PROVIDERS.indexOf(provider);
  check(i >= 0);
  check(
    credential.length > 0 && credential.length <= 512 && !/\s/.test(credential),
  );
  const review = spec.runs[i].review;
  return parseEvaluationReadiness({
    version: provider === "gemini"
      ? "evaluation_gemini_processor_v1"
      : "evaluation_openai_processor_v1",
    provider,
    corpusDigest: spec.corpusDigest,
    projectRef: provider === "gemini"
      ? "application-gemini-paid"
      : "naturebook-openai",
    credentialRef: provider === "gemini"
      ? "github-production-gemini-paid"
      : "github-production-naturebook-openai",
    credentialSha256: await fingerprintBytes(
      new TextEncoder().encode(credential),
    ),
    reviewedAt: review.reviewedAt,
    expiresAt: review.expiresAt,
    reviewerRole: "application-owner",
    dedicatedEvaluationProject: review.dedicatedEvaluationProject,
    paidServiceApproved: review.paidServiceApproved,
    purpose: "identification_evaluation",
    termsRef: review.termsRef,
    dataUseRef: review.dataUseRef,
    regionSubprocessorRef: review.regionSubprocessorRef,
    retentionAbuseLogRef: review.retentionAbuseLogRef,
    inputPermission: {
      provider,
      corpusDigest: spec.corpusDigest,
      caseIds: corpus.cases.map((c) => c.input.caseId),
      reviewRef: review.reviewRef,
      approved: review.inputPermissionApproved,
    },
  });
}

export async function prepareHostedExperiment(
  root: string,
  source: SourceIdentity,
  now = Date.now(),
) {
  await assertOfflinePermissions();
  const spec = parseHostedSpec(await readJson(join(root, "hosted-spec.json")));
  check(await fingerprintJson(spec.source) === await fingerprintJson(source));
  check(
    now >= Date.parse(spec.window.startsAt) &&
      now < Date.parse(spec.window.expiresAt),
  );
  const corpus = parseExploratoryCorpus(
    await readJson(join(root, "corpus.json")),
  );
  const runs = [];
  for (let i = 0; i < 2; i++) {
    const r = spec.runs[i];
    const readiness = parseEvaluationReadiness(
      await readJson(join(root, "approvals", `${HOSTED_RUNS[i]}.json`)),
    );
    check(
      readiness.version ===
        (i === 0
          ? "evaluation_gemini_processor_v1"
          : "evaluation_openai_processor_v1"),
    );
    check(
      readiness.corpusDigest === spec.corpusDigest &&
        Date.parse(readiness.expiresAt) > now,
    );
    runs.push({
      runId: HOSTED_RUNS[i],
      profileId: HOSTED_PROFILES[i],
      profileDigest: r.profileDigest,
      maxCalls: 8,
      budgetUsd: r.budgetUsd,
      pricing: r.pricing,
      pricingDigest: await fingerprintJson(r.pricing),
      readinessDigest: await fingerprintJson(readiness),
    });
  }
  const plan = parseExperimentPlan({
    version: "identification_experiment_plan_v1",
    experimentId: spec.experimentId,
    mode: "live",
    reviewRef: spec.publicRelease.reviewRef,
    source,
    corpusDigest: spec.corpusDigest,
    taxonomyDigest: spec.taxonomyDigest,
    preparationVersion: corpus.preparationVersion,
    orderSeed: spec.orderSeed,
    cases: await Promise.all(
      corpus.cases.map(async (c) => ({
        caseId: c.input.caseId,
        inputDigest: await fingerprintEvidence(c.input),
      })),
    ),
    window: spec.window,
    maxCalls: 16,
    budgetUsd: spec.budgetUsd,
    metrics: EXPERIMENT_METRICS,
    cacheControl: "automatic_uncontrolled_no_extra_requests",
    candidateDecision: "deferred_cache_isolation_and_explanation_rubric",
    runs,
  });
  await claimJson(join(root, "experiment.json"), plan);
  return await prepareExperiment(root, source, now);
}

/** Public-only preflight. It cannot construct readiness or authorize a dispatch. */
export async function checkHostedPacket(
  root: string,
  source: SourceIdentity,
  now = Date.now(),
) {
  await assertOfflinePermissions();
  const spec = parseHostedSpec(await readJson(join(root, "hosted-spec.json")));
  check(await fingerprintJson(spec.source) === await fingerprintJson(source));
  const corpus = parseExploratoryCorpus(
    await readJson(join(root, "corpus.json")),
  );
  check(await fingerprintJson(corpus) === spec.corpusDigest);
  check(
    await fingerprintJson(await readJson(join(root, "taxonomy.json"))) ===
      spec.taxonomyDigest,
  );
  check(now < Date.parse(spec.window.expiresAt));
  for (const [i, run] of spec.runs.entries()) {
    const age = now - Date.parse(run.pricing.retrievedAt);
    check(age >= 0 && age <= 7 * 86400000);
    check(
      (await reusableProfile(HOSTED_PROFILES[i])).digest === run.profileDigest,
    );
    let reservation = 0;
    for (const c of corpus.cases) {
      const assignment = await reusableAssignmentFor(
        c.input,
        await prepareEvidence(root, c.input),
        HOSTED_PROFILES[i],
        1,
        run.pricing,
      );
      reservation += reserveCost(run.pricing, assignment.model);
    }
    check(reservation <= run.budgetUsd);
  }
  await claimJson(join(root, "hosted-preflight.json"), {
    version: "hosted_identification_preflight_v1",
    source,
    corpusDigest: spec.corpusDigest,
    maxCalls: 16,
    budgetUsd: spec.budgetUsd,
    credentialBinding: "not_checked",
    dispatchAuthorized: false,
  });
}

export function bundleUrl(digest: string) {
  hash(digest);
  return `https://media.merian.app/${HOSTED_PREFIX}/bundles/${digest}.json`;
}
export function claimKey(experimentId: string) {
  safeId(experimentId);
  return `${HOSTED_PREFIX}/claims/${experimentId}.json`;
}
export interface HostedClaim {
  version: "hosted_identification_claim_v1";
  experimentId: string;
  bundleDigest: string;
  candidateSha: string;
  githubRunId: string;
  githubRunAttempt: string;
  maxCalls: 16;
  budgetUsd: number;
  expiresAt: string;
}
export function makeHostedClaim(
  spec: HostedSpec,
  digest: string,
  runId: string,
  attempt: string,
): HostedClaim {
  hash(digest);
  check(/^[1-9][0-9]{0,19}$/.test(runId) && /^[1-9][0-9]{0,5}$/.test(attempt));
  return {
    version: "hosted_identification_claim_v1",
    experimentId: spec.experimentId,
    bundleDigest: digest,
    candidateSha: spec.source.commit,
    githubRunId: runId,
    githubRunAttempt: attempt,
    maxCalls: 16,
    budgetUsd: spec.budgetUsd,
    expiresAt: spec.window.expiresAt,
  };
}
export async function assertHostedRunComplete(
  root: string,
  provider: HostedProvider,
) {
  const state = await readJson(join(root, "experiment", "state.json")) as {
    version?: unknown;
    stop?: unknown;
    completedRunIds?: unknown;
  };
  check(
    state.version === "identification_experiment_state_v1" &&
      state.stop === null && Array.isArray(state.completedRunIds) &&
      state.completedRunIds.includes(HOSTED_RUNS[PROVIDERS.indexOf(provider)]),
  );
}

/** Freshly regenerate reports; never publish approvals, manifests or arbitrary logs. */
export async function hostedPublicSummary(root: string, output: string) {
  await assertOfflinePermissions();
  const spec = parseHostedSpec(await readJson(join(root, "hosted-spec.json")));
  const binding = fields(await readJson(join(root, "bundle-binding.json")), [
    "digest",
  ]);
  hash(binding.digest);
  const claimed = await exists(join(root, "hosted-claim.json"));
  const publicPreflightPassed = await exists(
    join(root, "hosted-preflight.json"),
  );
  const claimAttempted = await exists(join(root, "hosted-claim-attempt.json"));
  let measurement = null;
  if (claimed && await exists(join(root, "experiment", "manifest.json"))) {
    try {
      const report = await saveExperimentReport(root);
      // These are generated projections of the normalized test records, not copied files.
      measurement = {
        complete: report.complete,
        evidenceStatus: report.evidenceStatus,
        accounting: report.accounting,
        cacheComparability: report.cacheComparability,
        productionQualified: false,
        runs: report.runs,
        comparisons: report.comparisons,
      };
    } catch {
      /* Missing/torn records retain the entire unknown allocation below. */
    }
  }
  const summary = {
    version: "hosted_identification_summary_v1",
    experimentId: spec.experimentId,
    bundleDigest: binding.digest,
    candidateSha: spec.source.commit,
    claimed,
    claimAttempted,
    publicPreflightPassed,
    complete: measurement?.complete ?? false,
    status: measurement?.complete
      ? "complete"
      : claimed
      ? "incomplete_no_replay"
      : claimAttempted
      ? "claim_unconfirmed_no_replay"
      : publicPreflightPassed
      ? "preflight_passed"
      : "not_started",
    maximumCalls: 16,
    budgetUsd: spec.budgetUsd,
    unresolvedAllocationUsd: (claimed || claimAttempted) && measurement === null
      ? spec.budgetUsd
      : null,
    productionQualified: false,
    measurement,
  };
  await privateDirectory(dirname(output));
  await atomicJson(output, summary);
  return summary;
}
