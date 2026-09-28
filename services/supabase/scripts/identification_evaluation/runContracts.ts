import {
  isOpenAIProfile,
  OPENAI_CANDIDATE_PROFILES,
  OPENAI_GENERATION,
  OPENAI_MODEL,
  OPENAI_NULL_FIELDS_PROFILE,
  OPENAI_PROFILE,
} from "../../functions/_shared/ai/openaiRequest.ts";
import { OPENAI_NULL_FIELDS_PROMPT } from "../../functions/_shared/ai/openaiNullFields.ts";
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
  token,
} from "./validation.ts";
import { EXPLORATORY_SPEC_VERSION } from "./exploratory.ts";

export const RUN_VERSION = "identification_run_v1" as const;
export const BOUNDARY = "prepared_evidence_to_normalized_decision_v1" as const;
export const GEMINI_PROFILES = ["gemini_flash_free", "gemini_pro"] as const;
export const PROFILES = [...GEMINI_PROFILES, OPENAI_PROFILE] as const;
export const PROVIDER_SPEC_VERSION =
  "identification_provider_run_spec_v1" as const;
export const PROVIDER_RUN_VERSION = "identification_provider_run_v1" as const;
export const CANDIDATE_SPEC_VERSION =
  "identification_provider_run_spec_v2" as const;
export const CANDIDATE_RUN_VERSION = "identification_provider_run_v2" as const;
export const NULL_FIELDS_SPEC_VERSION =
  "identification_provider_run_spec_v3" as const;
export const NULL_FIELDS_RUN_VERSION =
  "identification_provider_run_v3" as const;
export const MODEL_FOR_PROFILE = {
  [OPENAI_NULL_FIELDS_PROFILE]: OPENAI_MODEL,
  openai_photo_text_uncached_v1: OPENAI_MODEL,
  openai_photo_text_concise_uncached_v1: OPENAI_MODEL,
  gemini_flash_free: "gemini-2.5-flash",
  gemini_pro: "gemini-2.5-pro",
  [OPENAI_PROFILE]: OPENAI_MODEL,
} as const;
export function providerForProfile(profile: Profile): "gemini" | "openai" {
  return isOpenAIProfile(profile) ? "openai" : "gemini";
}
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

export { parseTaxonomy, type Taxonomy } from "./taxonomy.ts";
import {
  type IdentityMapping,
  parseIdentityMapping,
  type Taxonomy,
} from "./taxonomy.ts";

export function isMeasuredAttempt(record: { version: string }): boolean {
  return record.version === "evaluation_attempt_v2" ||
    record.version === "evaluation_openai_attempt_v2" ||
    record.version === "evaluation_openai_attempt_v3" ||
    record.version === "evaluation_openai_attempt_v4";
}
export function isOpenAIAttempt(record: { version: string }): boolean {
  return record.version === "evaluation_openai_attempt_v1" ||
    record.version === "evaluation_openai_attempt_v2" ||
    record.version === "evaluation_openai_attempt_v3" ||
    record.version === "evaluation_openai_attempt_v4";
}

export interface RunSpec {
  version:
    | "identification_run_spec_v1"
    | typeof EXPLORATORY_SPEC_VERSION
    | typeof PROVIDER_SPEC_VERSION
    | typeof CANDIDATE_SPEC_VERSION
    | typeof NULL_FIELDS_SPEC_VERSION;
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
    v.version === NULL_FIELDS_SPEC_VERSION ||
      v.version === CANDIDATE_SPEC_VERSION ||
      v.version === PROVIDER_SPEC_VERSION || v.version ===
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
  profiles.forEach((p) =>
    member(
      p,
      v.version === NULL_FIELDS_SPEC_VERSION
        ? [OPENAI_PROFILE, OPENAI_NULL_FIELDS_PROFILE] as const
        : v.version === CANDIDATE_SPEC_VERSION
        ? OPENAI_CANDIDATE_PROFILES
        : v.version === PROVIDER_SPEC_VERSION
        ? PROFILES
        : GEMINI_PROFILES,
    )
  );
  unique(profiles);
  if (
    v.version === CANDIDATE_SPEC_VERSION ||
    v.version === NULL_FIELDS_SPEC_VERSION
  ) {
    check(v.stage === "exploratory" && profiles.length === 1);
  }
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
    check(
      profiles.length ===
        (v.version === PROVIDER_SPEC_VERSION ||
            v.version === CANDIDATE_SPEC_VERSION ||
            v.version === NULL_FIELDS_SPEC_VERSION
          ? 1
          : 2),
    );
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
      v.dedicatedEvaluationProject === true,
  );
  return {
    ...parseReadinessReview(v),
    version: "evaluation_processor_v1",
    dedicatedEvaluationProject: true,
  };
}
function parseReadinessReview(
  v: Record<string, unknown>,
): Omit<Readiness, "version" | "dedicatedEvaluationProject"> {
  check(
    v.paidServiceApproved === true && v.purpose === "identification_evaluation",
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
  return structuredClone(v) as unknown as Omit<
    Readiness,
    "version" | "dedicatedEvaluationProject"
  >;
}

/** Provider-qualified evaluation records; legacy Gemini approvals never authorize OpenAI. */
export interface OpenAIPricing
  extends Omit<Pricing, "version" | "sourceUrl" | "models"> {
  version: "evaluation_openai_pricing_v1";
  provider: "openai";
  sourceUrl: "https://developers.openai.com/api/docs/models/gpt-6-sol";
  models: {
    model: typeof OPENAI_MODEL;
    inputPerMillion: {
      text: number;
      image: number;
      cached: number;
      cacheWrite: number;
    };
    outputPerMillion: number;
    maxInputTokens: number;
    maxBillableOutputTokens: number;
    limitsEvidenceRef: string;
  }[];
}
export type EvaluationPricing = Pricing | OpenAIPricing;
interface ProviderReadiness<P extends "gemini" | "openai">
  extends Omit<Readiness, "version" | "dedicatedEvaluationProject"> {
  provider: P;
  dedicatedEvaluationProject: boolean;
  inputPermission: {
    provider: P;
    corpusDigest: string;
    caseIds: string[];
    reviewRef: string;
    approved: true;
  };
}
export interface OpenAIReadiness extends ProviderReadiness<"openai"> {
  version: "evaluation_openai_processor_v1";
}
/** Explicit recipient/case review permits a shared paid Gemini project. */
export interface GeminiReadiness extends ProviderReadiness<"gemini"> {
  version: "evaluation_gemini_processor_v1";
}
export type EvaluationReadiness =
  | Readiness
  | OpenAIReadiness
  | GeminiReadiness;
export function parseEvaluationPricing(value: unknown): EvaluationPricing {
  if (
    (value as { version?: unknown } | null)?.version !==
      "evaluation_openai_pricing_v1"
  ) return parsePricing(value);
  const v = fields(value, [
    "version",
    "provider",
    "currency",
    "service",
    "retrievedAt",
    "sourceUrl",
    "reviewRef",
    "includesReasoning",
    "models",
  ]);
  check(
    v.provider === "openai" && v.currency === "USD" &&
      v.service === "paid_standard_synchronous" && v.includesReasoning === true,
  );
  timestamp(v.retrievedAt);
  token(v.reviewRef);
  check(
    v.sourceUrl === "https://developers.openai.com/api/docs/models/gpt-6-sol",
  );
  for (const raw of array(v.models, 1, 1)) {
    const m = fields(raw, [
      "model",
      "inputPerMillion",
      "outputPerMillion",
      "maxInputTokens",
      "maxBillableOutputTokens",
      "limitsEvidenceRef",
    ]);
    check(m.model === OPENAI_MODEL);
    const rates = fields(m.inputPerMillion, [
      "text",
      "image",
      "cached",
      "cacheWrite",
    ]);
    Object.values(rates).forEach((r) => number(r, 0.000001, 10000));
    number(m.outputPerMillion, 0.000001, 10000);
    // Reserve the entire model context because bytes are not a token bound.
    // The reviewed rates must cover long-context/cache-write pricing as well.
    integer(m.maxInputTokens, 1050000, 10000000);
    integer(
      m.maxBillableOutputTokens,
      OPENAI_GENERATION.maxOutputTokens,
      1000000,
    );
    token(m.limitsEvidenceRef);
  }
  return structuredClone(v) as unknown as OpenAIPricing;
}
export function parseEvaluationReadiness(value: unknown): EvaluationReadiness {
  const version = (value as { version?: unknown } | null)?.version;
  if (
    version !== "evaluation_openai_processor_v1" &&
    version !== "evaluation_gemini_processor_v1"
  ) return parseReadiness(value);
  const expectedProvider = version === "evaluation_openai_processor_v1"
    ? "openai"
    : "gemini";
  const { provider, inputPermission, dedicatedEvaluationProject, ...rest } =
    fields(value, [
      "version",
      "provider",
      "inputPermission",
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
    provider === expectedProvider &&
      typeof dedicatedEvaluationProject === "boolean",
  );
  const permission = fields(inputPermission, [
    "provider",
    "corpusDigest",
    "caseIds",
    "reviewRef",
    "approved",
  ]);
  check(
    permission.provider === expectedProvider && permission.approved === true,
  );
  hash(permission.corpusDigest);
  token(permission.reviewRef);
  const caseIds = array(permission.caseIds, 1, 240);
  caseIds.forEach((value) => id(value, "c"));
  unique(caseIds);
  const review = {
    ...parseReadinessReview(rest),
    dedicatedEvaluationProject,
  };
  return expectedProvider === "openai"
    ? {
      ...review,
      version: "evaluation_openai_processor_v1",
      provider: "openai",
      inputPermission: structuredClone(
        permission,
      ) as unknown as OpenAIReadiness["inputPermission"],
    }
    : {
      ...review,
      version: "evaluation_gemini_processor_v1",
      provider: "gemini",
      inputPermission: structuredClone(
        permission,
      ) as unknown as GeminiReadiness["inputPermission"],
    };
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
  model: typeof MODEL_FOR_PROFILE[Profile];
  prompt: string;
  schema: string;
  confidence: string;
  timeoutMs: number;
  generation: {
    temperature: number;
    maxOutputTokens: number;
    seed: number;
    thinkingBudget: number | null;
  } | typeof OPENAI_GENERATION;
  reservedUsd: number;
}
export function providerTransports(
  profiles: readonly Profile[],
  googleSdk: string,
): Record<string, string> {
  return Object.fromEntries(
    [...new Set(profiles.map(providerForProfile))].sort().map((
      provider,
    ) => [
      provider,
      provider === "openai" ? "openai_responses_https_v1" : googleSdk,
    ]),
  );
}
export interface RunManifest {
  version:
    | typeof RUN_VERSION
    | typeof PROVIDER_RUN_VERSION
    | typeof CANDIDATE_RUN_VERSION
    | typeof NULL_FIELDS_RUN_VERSION;
  boundary: typeof BOUNDARY;
  createdAt: string;
  spec: RunSpec;
  source: SourceIdentity;
  transports?: Record<string, string>;
  scorerVersion: string;
  taxonomyVersion: string;
  preparationVersion: string;
  pricing: EvaluationPricing | null;
  processor: { projectRef: string; credentialRef: string } | null;
  order: Assignment[];
}
export function parseManifest(value: unknown): RunManifest {
  const providerRun = [
    PROVIDER_RUN_VERSION,
    CANDIDATE_RUN_VERSION,
    NULL_FIELDS_RUN_VERSION,
  ].includes(
    (value as { version?: unknown } | null)
      ?.version as typeof PROVIDER_RUN_VERSION,
  );
  const v = fields(value, [
    "version",
    "boundary",
    "createdAt",
    "spec",
    "source",
    ...(providerRun ? ["transports"] : []),
    "scorerVersion",
    "taxonomyVersion",
    "preparationVersion",
    "pricing",
    "processor",
    "order",
  ]);
  check(
    [
      RUN_VERSION,
      PROVIDER_RUN_VERSION,
      CANDIDATE_RUN_VERSION,
      NULL_FIELDS_RUN_VERSION,
    ].includes(
      v.version as typeof RUN_VERSION,
    ) && v.boundary === BOUNDARY,
  );
  timestamp(v.createdAt);
  const spec = parseRunSpec(v.spec);
  check(
    v.version ===
      (spec.version === NULL_FIELDS_SPEC_VERSION
        ? NULL_FIELDS_RUN_VERSION
        : spec.version === CANDIDATE_SPEC_VERSION
        ? CANDIDATE_RUN_VERSION
        : spec.version === PROVIDER_SPEC_VERSION
        ? PROVIDER_RUN_VERSION
        : RUN_VERSION),
  );
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
  if (providerRun) {
    const expected = providerTransports(spec.profiles, source.sdk);
    const transports = fields(v.transports, Object.keys(expected));
    check(
      Object.entries(expected).every(([provider, transport]) =>
        transports[provider] === transport
      ),
    );
  }
  for (const k of ["scorerVersion", "taxonomyVersion", "preparationVersion"]) {
    token(v[k]);
  }
  if (spec.mode === "live") {
    const pricing = parseEvaluationPricing(v.pricing);
    check(
      (pricing.version === "evaluation_openai_pricing_v1") ===
        isOpenAIProfile(spec.profiles[0]),
    );
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
    check(a.model === MODEL_FOR_PROFILE[a.profile]);
    for (const k of ["prompt", "schema", "confidence"]) token(a[k]);
    integer(a.timeoutMs, 1, 120000);
    number(a.reservedUsd);
    if (isOpenAIProfile(a.profile)) {
      const g = fields(a.generation, [
        "maxOutputTokens",
        "reasoningEffort",
        "imageDetail",
      ]);
      check(
        g.maxOutputTokens === OPENAI_GENERATION.maxOutputTokens &&
          g.reasoningEffort === OPENAI_GENERATION.reasoningEffort &&
          g.imageDetail === OPENAI_GENERATION.imageDetail,
      );
      check(
        a.confidence === "openai_unqualified_v1" &&
          a.schema === "merian_openai_identify_v1" &&
          (a.profile === OPENAI_NULL_FIELDS_PROFILE
            ? [OPENAI_NULL_FIELDS_PROMPT]
            : a.profile === "openai_photo_text_concise_uncached_v1"
            ? [
              "openai_concise_identify_vision_v1",
              "openai_concise_identify_text_v1",
            ]
            : ["openai_identify_vision_v1", "openai_identify_text_v1"])
            .includes(a.prompt as string) &&
          a.timeoutMs === 90000,
      );
    } else {
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
  cacheWriteTokens?: number | null;
  modalities: {
    prompt: TokenModalities;
    cached: TokenModalities;
    candidates: TokenModalities;
    tool: TokenModalities;
  } | null;
}
export type TokenModalities = { text: number; image: number; audio: number };
export interface AttemptRecord {
  version:
    | "evaluation_attempt_v1"
    | "evaluation_openai_attempt_v1"
    | "evaluation_attempt_v2"
    | "evaluation_openai_attempt_v2"
    | "evaluation_openai_attempt_v3"
    | "evaluation_openai_attempt_v4";
  mapping?: IdentityMapping | null;
  candidateMappings?: IdentityMapping[] | null;
  runDigest: string;
  key: string;
  prediction: Prediction;
  reason: Reason;
  returnedModel: string | null;
  band: "below_possible" | "possible" | "strong" | "unqualified" | null;
  diagnostic: boolean;
  candidates: { taxon: Taxon | null; confidence: number }[] | null;
  usage: StoredUsage | null;
  providerMs: number | null;
  normalizationMs: number | null;
  estimatedUpperUsd: number | null;
}
export function parseAttempt(value: unknown): AttemptRecord {
  const measured = isMeasuredAttempt({
    version: String((value as { version?: unknown } | null)?.version),
  });
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
    ...(measured ? ["mapping", "candidateMappings"] : []),
  ]);
  check(
    measured || v.version === "evaluation_attempt_v1" ||
      isOpenAIAttempt({ version: String(v.version) }),
  );
  hash(v.runDigest);
  token(v.key);
  const candidateKey = OPENAI_CANDIDATE_PROFILES.some((p) =>
    new RegExp(`^c[0-9]{4,12}-${p}-[12]$`).test(v.key as string)
  );
  check((v.version === "evaluation_openai_attempt_v3") === candidateKey);
  const nullFieldsKey = new RegExp(
    "^c[0-9]{4,12}-" + OPENAI_NULL_FIELDS_PROFILE + "-[12]$",
  ).test(v.key as string);
  check((v.version === "evaluation_openai_attempt_v4") === nullFieldsKey);
  const prediction = parsePrediction(v.prediction);
  member(v.reason, REASONS);
  check(
    v.returnedModel === null ||
      typeof v.returnedModel === "string" &&
        (isOpenAIAttempt({ version: String(v.version) })
          ? /^gpt-6-sol(?:-[a-zA-Z0-9.-]{1,80})?$/
          : /^gemini-[a-zA-Z0-9.-]{1,100}$/).test(v.returnedModel),
  );
  member(
    v.band,
    isOpenAIAttempt({ version: String(v.version) })
      ? [null, "unqualified"]
      : [null, "below_possible", "possible", "strong"],
  );
  if (isOpenAIAttempt({ version: String(v.version) })) {
    check(v.diagnostic === false);
  }
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
      ...(measured ? ["cacheWriteTokens"] : []),
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
  if (measured) {
    if (prediction.outcome !== "normalized") {
      check(v.mapping === null && v.candidateMappings === null);
    } else {
      const mapping = parseIdentityMapping(v.mapping, prediction.taxon);
      const named = prediction.subject === "biological" &&
        prediction.resolution === "named";
      check(
        named
          ? mapping.status !== "not_applicable"
          : mapping.status === "not_applicable",
      );
      if (v.candidates === null) check(v.candidateMappings === null);
      else {
        const mappings = array(v.candidateMappings, 0, 5);
        const candidates = v.candidates as { taxon: Taxon | null }[];
        check(mappings.length === candidates.length);
        mappings.forEach((mapping, i) =>
          check(
            parseIdentityMapping(mapping, candidates[i].taxon).status !==
              "not_applicable",
          )
        );
      }
    }
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
