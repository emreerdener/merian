import {
  type Prediction,
  type Profile,
  RANKS,
  type Split,
  type Taxon,
} from "./contracts.ts";
import {
  array,
  fields,
  id,
  integer,
  member,
  parsePrediction,
  requireCondition as check,
  taxon,
  text,
  token,
} from "./validation.ts";
import { EXPLORATORY_SPEC_VERSION } from "./exploratory.ts";

export const RUN_VERSION = "identification_run_v1" as const;
export const BOUNDARY = "prepared_evidence_to_normalized_decision_v1" as const;
export const PROFILES = ["gemini_flash_free", "gemini_pro"] as const;
export const MODELS = ["gemini-2.5-flash", "gemini-2.5-pro"] as const;
export const STAGE_LIMITS = {
  exploratory: 24,
  development: 120,
  held_out: 480,
  repeatability: 120,
} as const;
export const REASONS = [
  "completed",
  "refusal",
  "invalid_output",
  "operational_failure",
  "unknown_execution",
  "normalization_failed",
  "unattempted",
  "usage_missing",
  "model_mismatch",
  "budget_exceeded",
  "call_limit",
  "interrupted_attempt",
] as const;
export type Reason = typeof REASONS[number];

export function hash(value: unknown): asserts value is string {
  check(typeof value === "string" && /^[a-f0-9]{64}$/.test(value));
}
export function number(
  value: unknown,
  min = 0,
  max = 1e12,
): asserts value is number {
  check(
    typeof value === "number" && Number.isFinite(value) && value >= min &&
      value <= max,
  );
}
export function timestamp(value: unknown): asserts value is string {
  check(
    typeof value === "string" &&
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) &&
      Number.isFinite(Date.parse(value)),
  );
}
export function unique<T>(values: readonly T[]): void {
  check(new Set(values).size === values.length);
}

export interface Taxonomy {
  version: "evaluation_taxonomy_v1";
  taxonomyVersion: string;
  taxa: { taxon: Taxon; names: string[] }[];
}
export function parseTaxonomy(value: unknown): Taxonomy {
  const v = fields(value, ["version", "taxonomyVersion", "taxa"]);
  check(v.version === "evaluation_taxonomy_v1");
  token(v.taxonomyVersion);
  const names: string[] = [], ids: string[] = [];
  for (const raw of array(v.taxa, 1, 100000)) {
    const item = fields(raw, ["taxon", "names"]);
    const t = taxon(item.taxon);
    ids.push(t.id);
    for (const name of array(item.names, 1, 32)) {
      text(name, 255);
      names.push(name.toLowerCase());
    }
  }
  unique(ids);
  unique(names);
  return structuredClone(v) as unknown as Taxonomy;
}

export interface RunSpec {
  version: "identification_run_spec_v1" | typeof EXPLORATORY_SPEC_VERSION;
  runId: string;
  mode: "offline" | "live";
  corpusDigest: string;
  taxonomyDigest: string;
  split: Split;
  stage: keyof typeof STAGE_LIMITS;
  profiles: Profile[];
  caseIds: string[];
  repeats: 1 | 2;
  orderSeed: number;
  maxCalls: number;
  budgetUsd: number;
  pricingDigest: string | null;
  readinessDigest: string | null;
}
export function parseRunSpec(value: unknown): RunSpec {
  const v = fields(value, [
    "version",
    "runId",
    "mode",
    "corpusDigest",
    "taxonomyDigest",
    "split",
    "stage",
    "profiles",
    "caseIds",
    "repeats",
    "orderSeed",
    "maxCalls",
    "budgetUsd",
    "pricingDigest",
    "readinessDigest",
  ]);
  check(
    v.version ===
      (v.stage === "exploratory"
        ? EXPLORATORY_SPEC_VERSION
        : "identification_run_spec_v1"),
  );
  token(v.runId);
  member(v.mode, ["offline", "live"]);
  hash(v.corpusDigest);
  hash(v.taxonomyDigest);
  member(v.split, ["development", "held_out"]);
  member(v.stage, Object.keys(STAGE_LIMITS) as (keyof typeof STAGE_LIMITS)[]);
  const profiles = array(v.profiles, 1, 2);
  profiles.forEach((p) => member(p, PROFILES));
  unique(profiles);
  const ids = array(v.caseIds, 1, 240);
  if (v.stage === "exploratory") check(ids.length <= 12);
  ids.forEach((x) => id(x, "c"));
  unique(ids);
  integer(v.orderSeed, 0, 0xffffffff);
  integer(v.maxCalls, 1, STAGE_LIMITS[v.stage]);
  check(v.repeats === (v.stage === "repeatability" ? 2 : 1));
  check(v.split === (v.stage === "held_out" ? "held_out" : "development"));
  number(v.budgetUsd, 0, 100000);
  if (v.mode === "live") {
    check(v.budgetUsd > 0);
    hash(v.pricingDigest);
    hash(v.readinessDigest);
    check(profiles.length === 2);
  } else {check(
      v.budgetUsd === 0 && v.pricingDigest === null &&
        v.readinessDigest === null,
    );}
  return structuredClone(v) as unknown as RunSpec;
}

/** Reviewed worst-case rates across synchronous context tiers; no price defaults. */
export interface Pricing {
  version: "evaluation_pricing_v1";
  currency: "USD";
  service: "paid_standard_synchronous";
  retrievedAt: string;
  sourceUrl: "https://ai.google.dev/gemini-api/docs/pricing";
  reviewRef: string;
  includesReasoning: true;
  models: {
    model: typeof MODELS[number];
    inputPerMillion: {
      text: number;
      image: number;
      audio: number;
      cached: number;
    };
    outputPerMillion: number;
    maxInputTokens: number;
    maxBillableOutputTokens: number;
    limitsEvidenceRef: string;
  }[];
}
export function parsePricing(value: unknown): Pricing {
  const v = fields(value, [
    "version",
    "currency",
    "service",
    "retrievedAt",
    "sourceUrl",
    "reviewRef",
    "includesReasoning",
    "models",
  ]);
  check(
    v.version === "evaluation_pricing_v1" && v.currency === "USD" &&
      v.service === "paid_standard_synchronous" && v.includesReasoning === true,
  );
  timestamp(v.retrievedAt);
  token(v.reviewRef);
  check(v.sourceUrl === "https://ai.google.dev/gemini-api/docs/pricing");
  const models: string[] = [];
  for (const raw of array(v.models, 2, 2)) {
    const m = fields(raw, [
      "model",
      "inputPerMillion",
      "outputPerMillion",
      "maxInputTokens",
      "maxBillableOutputTokens",
      "limitsEvidenceRef",
    ]);
    member(m.model, MODELS);
    models.push(m.model);
    const rates = fields(m.inputPerMillion, [
      "text",
      "image",
      "audio",
      "cached",
    ]);
    Object.values(rates).forEach((r) => number(r, 0.000001, 10000));
    number(m.outputPerMillion, 0.000001, 10000);
    integer(m.maxInputTokens, 1, 10000000);
    integer(m.maxBillableOutputTokens, 8192, 1000000);
    token(m.limitsEvidenceRef);
  }
  unique(models);
  return structuredClone(v) as unknown as Pricing;
}
export interface Readiness {
  version: "evaluation_processor_v1";
  corpusDigest: string;
  projectRef: string;
  credentialRef: string;
  credentialSha256: string;
  reviewedAt: string;
  expiresAt: string;
  reviewerRole: string;
  dedicatedEvaluationProject: true;
  paidServiceApproved: true;
  purpose: "identification_evaluation";
  termsRef: string;
  dataUseRef: string;
  regionSubprocessorRef: string;
  retentionAbuseLogRef: string;
}
export function parseReadiness(value: unknown): Readiness {
  const v = fields(value, [
    "version",
    "corpusDigest",
    "projectRef",
    "credentialRef",
    "credentialSha256",
    "reviewedAt",
    "expiresAt",
    "reviewerRole",
    "dedicatedEvaluationProject",
    "paidServiceApproved",
    "purpose",
    "termsRef",
    "dataUseRef",
    "regionSubprocessorRef",
    "retentionAbuseLogRef",
  ]);
  check(
    v.version === "evaluation_processor_v1" &&
      v.dedicatedEvaluationProject === true && v.paidServiceApproved === true &&
      v.purpose === "identification_evaluation",
  );
  hash(v.corpusDigest);
  hash(v.credentialSha256);
  timestamp(v.reviewedAt);
  timestamp(v.expiresAt);
  for (
    const k of [
      "projectRef",
      "credentialRef",
      "reviewerRole",
      "termsRef",
      "dataUseRef",
      "regionSubprocessorRef",
      "retentionAbuseLogRef",
    ]
  ) token(v[k]);
  return structuredClone(v) as unknown as Readiness;
}

export interface SourceIdentity {
  commit: string;
  dirty: boolean;
  digest: string;
  sdk: string;
}
export interface Assignment {
  key: string;
  caseId: string;
  profile: Profile;
  attempt: number;
  inputDigest: string;
  requestDigest: string;
  policyDigest: string;
  promptDigest: string;
  schemaDigest: string;
  confidenceDigest: string;
  model: typeof MODELS[number];
  prompt: string;
  schema: string;
  confidence: string;
  timeoutMs: number;
  generation: {
    temperature: number;
    maxOutputTokens: number;
    seed: number;
    thinkingBudget: number | null;
  };
  reservedUsd: number;
}
export interface RunManifest {
  version: typeof RUN_VERSION;
  boundary: typeof BOUNDARY;
  createdAt: string;
  spec: RunSpec;
  source: SourceIdentity;
  scorerVersion: string;
  taxonomyVersion: string;
  preparationVersion: string;
  pricing: Pricing | null;
  processor: { projectRef: string; credentialRef: string } | null;
  order: Assignment[];
}
export function parseManifest(value: unknown): RunManifest {
  const v = fields(value, [
    "version",
    "boundary",
    "createdAt",
    "spec",
    "source",
    "scorerVersion",
    "taxonomyVersion",
    "preparationVersion",
    "pricing",
    "processor",
    "order",
  ]);
  check(v.version === RUN_VERSION && v.boundary === BOUNDARY);
  timestamp(v.createdAt);
  const spec = parseRunSpec(v.spec);
  const source = fields(v.source, ["commit", "dirty", "digest", "sdk"]);
  check(
    typeof source.commit === "string" && /^[a-f0-9]{40}$/.test(source.commit),
  );
  check(typeof source.dirty === "boolean");
  hash(source.digest);
  check(
    typeof source.sdk === "string" &&
      /^npm:@google\/genai@\d+\.\d+\.\d+$/.test(source.sdk),
  );
  for (const k of ["scorerVersion", "taxonomyVersion", "preparationVersion"]) {
    token(v[k]);
  }
  if (spec.mode === "live") {
    parsePricing(v.pricing);
    const processor = fields(v.processor, ["projectRef", "credentialRef"]);
    token(processor.projectRef);
    token(processor.credentialRef);
  } else check(v.pricing === null && v.processor === null);
  const keys: string[] = [];
  for (const raw of array(v.order, 1, STAGE_LIMITS[spec.stage])) {
    const a = fields(raw, [
      "key",
      "caseId",
      "profile",
      "attempt",
      "inputDigest",
      "requestDigest",
      "policyDigest",
      "promptDigest",
      "schemaDigest",
      "confidenceDigest",
      "model",
      "prompt",
      "schema",
      "confidence",
      "timeoutMs",
      "generation",
      "reservedUsd",
    ]);
    id(a.caseId, "c");
    member(a.profile, spec.profiles);
    integer(a.attempt, 1, spec.repeats);
    check(spec.caseIds.includes(a.caseId));
    check(a.key === `${a.caseId}-${a.profile}-${a.attempt}`);
    keys.push(a.key as string);
    for (
      const k of [
        "inputDigest",
        "requestDigest",
        "policyDigest",
        "promptDigest",
        "schemaDigest",
        "confidenceDigest",
      ]
    ) hash(a[k]);
    member(a.model, MODELS);
    check(a.model === (a.profile === "gemini_pro" ? MODELS[1] : MODELS[0]));
    for (const k of ["prompt", "schema", "confidence"]) token(a[k]);
    integer(a.timeoutMs, 1, 120000);
    number(a.reservedUsd);
    const g = fields(a.generation, [
      "temperature",
      "maxOutputTokens",
      "seed",
      "thinkingBudget",
    ]);
    number(g.temperature, 0, 2);
    integer(g.maxOutputTokens, 1, 1000000);
    integer(g.seed, 0, 0xffffffff);
    if (g.thinkingBudget !== null) integer(g.thinkingBudget, 0, 1000000);
  }
  unique(keys);
  check(
    keys.length === spec.caseIds.length * spec.profiles.length * spec.repeats,
  );
  return structuredClone(v) as unknown as RunManifest;
}

export interface StoredUsage {
  promptTokens: number | null;
  candidateTokens: number | null;
  totalTokens: number | null;
  thinkingTokens: number | null;
  cachedTokens: number | null;
  toolTokens: number | null;
  modalities: {
    prompt: TokenModalities;
    cached: TokenModalities;
    candidates: TokenModalities;
    tool: TokenModalities;
  } | null;
}
export type TokenModalities = { text: number; image: number; audio: number };
export interface AttemptRecord {
  version: "evaluation_attempt_v1";
  runDigest: string;
  key: string;
  prediction: Prediction;
  reason: Reason;
  returnedModel: string | null;
  band: "below_possible" | "possible" | "strong" | null;
  diagnostic: boolean;
  candidates: { taxon: Taxon | null; confidence: number }[] | null;
  usage: StoredUsage | null;
  providerMs: number | null;
  normalizationMs: number | null;
  estimatedUpperUsd: number | null;
}
export function parseAttempt(value: unknown): AttemptRecord {
  const v = fields(value, [
    "version",
    "runDigest",
    "key",
    "prediction",
    "reason",
    "returnedModel",
    "band",
    "diagnostic",
    "candidates",
    "usage",
    "providerMs",
    "normalizationMs",
    "estimatedUpperUsd",
  ]);
  check(v.version === "evaluation_attempt_v1");
  hash(v.runDigest);
  token(v.key);
  const prediction = parsePrediction(v.prediction);
  member(v.reason, REASONS);
  check(
    v.returnedModel === null ||
      typeof v.returnedModel === "string" &&
        /^gemini-[a-zA-Z0-9.-]{1,100}$/.test(v.returnedModel),
  );
  member(v.band, [null, "below_possible", "possible", "strong"]);
  check(typeof v.diagnostic === "boolean");
  if (v.candidates !== null) {
    for (const raw of array(v.candidates, 0, 5)) {
      const c = fields(raw, ["taxon", "confidence"]);
      if (c.taxon !== null) taxon(c.taxon);
      number(c.confidence, 0, 1);
    }
  }
  if (v.usage !== null) {
    const u = fields(v.usage, [
      "promptTokens",
      "candidateTokens",
      "totalTokens",
      "thinkingTokens",
      "cachedTokens",
      "toolTokens",
      "modalities",
    ]);
    for (const [key, item] of Object.entries(u)) {
      if (key === "modalities") continue;
      if (item !== null) integer(item, 0, 100000000);
    }
    if (u.modalities !== null) {
      const m = fields(u.modalities, [
        "prompt",
        "cached",
        "candidates",
        "tool",
      ]);
      for (const value of Object.values(m)) {
        const counts = fields(value, ["text", "image", "audio"]);
        Object.values(counts).forEach((n) => integer(n, 0, 100000000));
      }
    }
  }
  for (const k of ["providerMs", "normalizationMs", "estimatedUpperUsd"]) {
    if (v[k] !== null) number(v[k]);
  }
  if (prediction.outcome !== "normalized") {
    check(
      v.band === null && v.diagnostic === false && v.candidates === null &&
        v.normalizationMs === null,
    );
  } else check(v.band !== null && v.normalizationMs !== null);
  if (prediction.outcome === "unattempted") {
    check(
      v.providerMs === null && v.usage === null && v.estimatedUpperUsd === null,
    );
  }
  if (v.reason === "completed") check(prediction.outcome === "normalized");
  if (
    ["refusal", "invalid_output", "operational_failure", "unknown_execution"]
      .includes(v.reason)
  ) check(prediction.outcome === v.reason);
  if (v.reason === "normalization_failed") {
    check(prediction.outcome === "invalid_output");
  }
  if (v.reason === "interrupted_attempt") {
    check(prediction.outcome === "unknown_execution");
  }
  if (["budget_exceeded", "call_limit", "unattempted"].includes(v.reason)) {
    check(prediction.outcome === "unattempted");
  }
  return structuredClone(v) as unknown as AttemptRecord;
}

export interface StartedClaim {
  version: "evaluation_started_v1";
  runDigest: string;
  key: string;
  requestDigest: string;
  reservedUsd: number;
  startedAt: string;
}
export function parseClaim(
  value: unknown,
  assignment: Assignment,
  runDigest: string,
): StartedClaim {
  const v = fields(value, [
    "version",
    "runDigest",
    "key",
    "requestDigest",
    "reservedUsd",
    "startedAt",
  ]);
  check(
    v.version === "evaluation_started_v1" && v.runDigest === runDigest &&
      v.key === assignment.key &&
      v.requestDigest === assignment.requestDigest &&
      v.reservedUsd === assignment.reservedUsd,
  );
  timestamp(v.startedAt);
  return v as unknown as StartedClaim;
}

export function referenceTaxaExist(
  taxonomy: Taxonomy,
  values: readonly Taxon[],
): boolean {
  return values.every((t) =>
    RANKS.includes(t.rank) &&
    taxonomy.taxa.some((item) =>
      item.taxon.id === t.id && item.taxon.rank === t.rank
    )
  );
}
