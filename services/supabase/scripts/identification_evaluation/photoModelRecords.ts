/** Content-free journal for the new photo comparison; legacy records stay closed. */
import type {
  AIProviderOutcome,
  AIUsage,
} from "../../functions/_shared/ai/contracts.ts";
import { normalizeIdentification } from "../../functions/_shared/identify/normalizeIdentification.ts";
import type { EvaluationInput, Prediction } from "./contracts.ts";
import { normalizedExplanationDisplay } from "./explanationReview.ts";
import type { ReviewDisplay } from "./explanationView.ts";
import type { FactCard } from "./explanationContracts.ts";
import type { MultimodalAIRequest } from "../../functions/_shared/ai/contracts.ts";
import {
  PHOTO_MODEL_TOKEN_CEILINGS,
  photoModelPrice,
  type PhotoModelPricing,
} from "./photoModelContracts.ts";
import type { PhotoModelAssignment } from "./photoModelPreparation.ts";
import { hash, number, type Taxonomy } from "./runContracts.ts";
import {
  type IdentityMapping,
  noIdentityMapping,
  parseIdentityMapping,
  resolveTaxon,
} from "./taxonomy.ts";
import {
  fields,
  integer,
  member,
  parsePrediction,
  requireCondition as check,
} from "./validation.ts";

// Reserve the published regional premium even if the account is billed globally.
export const PHOTO_MODEL_BILLING_MULTIPLIER = 1.1;
export const PHOTO_MODEL_REASONS = [
  "completed",
  "refusal",
  "invalid_output",
  "operational_failure",
  "unknown_execution",
  "model_mismatch",
  "safety_unavailable",
  "usage_missing",
  "normalization_failed",
] as const;
export type PhotoModelReason = typeof PHOTO_MODEL_REASONS[number];
interface PhotoUsage {
  input: number | null;
  output: number | null;
  reasoning: number | null;
  cached: number | null;
  cacheWrite: number | null;
  total: number | null;
  tools: number | null;
}
export interface PhotoModelRecord {
  version: "photo_model_attempt_v1";
  runDigest: string;
  assignmentDigest: string;
  ordinal: number;
  reason: PhotoModelReason;
  prediction: Prediction;
  returnedModel: string | null;
  serviceTier: "default" | null;
  safety: "allowed" | "rejected" | "unavailable";
  usage: PhotoUsage | null;
  providerMs: number | null;
  normalizationMs: number | null;
  estimatedUpperNanoUsd: number | null;
}
const count = (n: unknown): number | null =>
  typeof n === "number" && Number.isSafeInteger(n) && n >= 0 && n <= 100_000_000
    ? n
    : null;
const duration = (n: unknown): number | null =>
  typeof n === "number" && Number.isFinite(n) && n >= 0 && n <= 1e12 ? n : null;
function usageProjection(u: AIUsage | null): PhotoUsage | null {
  return u
    ? {
      input: count(u.promptTokens),
      output: count(u.outputTokens),
      reasoning: count(u.thinkingTokens),
      cached: count(u.cachedTokens),
      cacheWrite: count(u.cacheWriteTokens),
      total: count(u.totalTokens),
      tools: count(u.toolTokens),
    }
    : null;
}
export function photoModelCostUpper(
  usage: PhotoUsage | null,
  a: PhotoModelAssignment,
  pricing: PhotoModelPricing,
): number | null {
  if (!usage || Object.values(usage).some((n) => n === null)) return null;
  const { input, output, reasoning, cached, cacheWrite, total, tools } =
    usage as Record<keyof PhotoUsage, number>;
  if (
    input > PHOTO_MODEL_TOKEN_CEILINGS.input ||
    output > PHOTO_MODEL_TOKEN_CEILINGS.output ||
    total !== input + output || reasoning > output ||
    cached + cacheWrite > input || tools !== 0
  ) return null;
  const p = photoModelPrice(a.profile, pricing);
  // Output already includes reasoning. No cache discount is assumed for this upper bound.
  return Math.ceil(
    (input * p.inputCeilingUsdPerMillion +
      output * p.outputCeilingUsdPerMillion) *
      1000 * PHOTO_MODEL_BILLING_MULTIPLIER,
  );
}
const PHOTO_MODEL_RECORD_FIELDS = [
  "version",
  "runDigest",
  "assignmentDigest",
  "ordinal",
  "reason",
  "prediction",
  "returnedModel",
  "serviceTier",
  "safety",
  "usage",
  "providerMs",
  "normalizationMs",
  "estimatedUpperNanoUsd",
] as const;

export function parsePhotoModelRecord(
  value: unknown,
  a: PhotoModelAssignment,
  runDigest: string,
  assignmentDigest: string,
): PhotoModelRecord {
  const v = fields(value, PHOTO_MODEL_RECORD_FIELDS);
  check(
    v.version === "photo_model_attempt_v1" && v.runDigest === runDigest &&
      v.assignmentDigest === assignmentDigest && v.ordinal === a.ordinal,
  );
  hash(v.runDigest);
  hash(v.assignmentDigest);
  member(v.reason, PHOTO_MODEL_REASONS);
  const prediction = parsePrediction(v.prediction);
  check(prediction.caseId === a.caseId);
  member(v.returnedModel, [null, a.model]);
  member(v.serviceTier, [null, "default"]);
  member(v.safety, ["allowed", "rejected", "unavailable"]);
  if (v.usage !== null) {
    const u = fields(v.usage, [
      "input",
      "output",
      "reasoning",
      "cached",
      "cacheWrite",
      "total",
      "tools",
    ]);
    for (const n of Object.values(u)) {
      if (n !== null) integer(n, 0, 100_000_000);
    }
  }
  for (const k of ["providerMs", "normalizationMs"]) {
    if (v[k] !== null) number(v[k], 0, 1e12);
  }
  if (v.estimatedUpperNanoUsd !== null) {
    integer(v.estimatedUpperNanoUsd, 0, Number.MAX_SAFE_INTEGER);
  }
  check(
    v.reason !== "completed" ||
      (prediction.outcome === "normalized" && v.returnedModel === a.model &&
        v.serviceTier === "default" && v.safety === "allowed" &&
        v.usage !== null && v.estimatedUpperNanoUsd !== null),
  );
  return structuredClone(v) as unknown as PhotoModelRecord;
}
function projectPhotoModelOutcomeWithMapping(
  outcome: AIProviderOutcome,
  input: EvaluationInput,
  request: MultimodalAIRequest,
  card: FactCard,
  a: PhotoModelAssignment,
  runDigest: string,
  assignmentDigest: string,
  taxonomy: Taxonomy,
  pricing: PhotoModelPricing,
): {
  record: PhotoModelRecord;
  display: ReviewDisplay | null;
  mapping: IdentityMapping;
} {
  const record: PhotoModelRecord = {
    version: "photo_model_attempt_v1",
    runDigest,
    assignmentDigest,
    ordinal: a.ordinal,
    reason: outcome.kind === "draft" ? "completed" : outcome.kind,
    prediction: {
      caseId: a.caseId,
      outcome: outcome.kind === "draft" ? "invalid_output" : outcome.kind,
    },
    returnedModel: outcome.returnedModel === a.model ? a.model : null,
    serviceTier: outcome.serviceTier === "default" ? "default" : null,
    safety: outcome.mediaSafety?.disposition ?? "unavailable",
    usage: usageProjection(outcome.usage),
    providerMs: duration(outcome.providerDurationMs),
    normalizationMs: null,
    estimatedUpperNanoUsd: null,
  };
  if (record.returnedModel === a.model && record.serviceTier === "default") {
    record.estimatedUpperNanoUsd = photoModelCostUpper(
      record.usage,
      a,
      pricing,
    );
  }
  let display: ReviewDisplay | null = null;
  let mapping = noIdentityMapping();
  // The production-equivalent decoder has already removed unsafe/mismatched drafts.
  if (outcome.kind === "invalid_output" && outcome.reason === "safety") {
    record.reason = record.returnedModel !== a.model
      ? "model_mismatch"
      : "safety_unavailable";
  }
  if (outcome.kind === "draft") {
    if (record.returnedModel !== a.model) record.reason = "model_mismatch";
    else if (record.safety !== "allowed") record.reason = "safety_unavailable";
    else {
      const start = performance.now();
      try {
        check(
          input.inputGroup === "photos" &&
            input.assets.every((asset) => asset.kind === "image"),
        );
        const normalized = normalizeIdentification(outcome.draft, {
          hasVisualEvidence: true,
          hasAudioEvidence: false,
          hasInvasiveLocationContext: false,
          confidencePolicy: { kind: "unqualified" },
        });
        const v = normalized.identification;
        const subject = v.is_biological_subject
          ? v.scientific_name?.toLowerCase() === "homo sapiens"
            ? "human"
            : "biological"
          : "non_biological";
        const named = subject === "biological" && !!v.scientific_name;
        const identity = named
          ? resolveTaxon(taxonomy, v.scientific_name!)
          : { taxon: null, mapping: noIdentityMapping() };
        mapping = identity.mapping;
        record.prediction = {
          caseId: a.caseId,
          outcome: "normalized",
          subject,
          resolution: named ? "named" : "unresolved",
          taxon: identity.taxon,
          confidence: v.confidence_score ?? 0,
        };
        record.normalizationMs = duration(performance.now() - start);
        display = normalizedExplanationDisplay(normalized, request, card);
        if (record.estimatedUpperNanoUsd === null) {
          record.reason = "usage_missing";
        }
      } catch {
        record.reason = "normalization_failed";
        mapping = noIdentityMapping();
        record.prediction = { caseId: a.caseId, outcome: "invalid_output" };
        record.normalizationMs = null;
      }
    }
  }
  return {
    record: parsePhotoModelRecord(record, a, runDigest, assignmentDigest),
    display,
    mapping,
  };
}

/** Existing v1 plans and journals keep the exact v1 projection. */
export function projectPhotoModelOutcome(
  ...args: Parameters<typeof projectPhotoModelOutcomeWithMapping>
): { record: PhotoModelRecord; display: ReviewDisplay | null } {
  const { record, display } = projectPhotoModelOutcomeWithMapping(...args);
  return { record, display };
}

export type PhotoModelMeasurementRecord =
  & Omit<PhotoModelRecord, "version">
  & { version: "photo_model_attempt_v2"; mapping: IdentityMapping };

/** Sol-rank journals bind v2 explicitly; historical runners still reject it. */
export function parsePhotoModelMeasurementRecord(
  value: unknown,
  a: PhotoModelAssignment,
  runDigest: string,
  assignmentDigest: string,
): PhotoModelMeasurementRecord {
  // Validate the full legacy shape as well: extra output/prose fields fail closed.
  const { version, mapping, ...base } = fields(value, [
    ...PHOTO_MODEL_RECORD_FIELDS,
    "mapping",
  ]);
  check(version === "photo_model_attempt_v2");
  const record = parsePhotoModelRecord(
    { ...base, version: "photo_model_attempt_v1" },
    a,
    runDigest,
    assignmentDigest,
  );
  const p = record.prediction;
  const named = p.outcome === "normalized" && p.resolution === "named";
  const parsedMapping = parseIdentityMapping(
    mapping,
    p.outcome === "normalized" ? p.taxon : null,
  );
  check(named === (parsedMapping.status !== "not_applicable"));
  return { ...record, version, mapping: parsedMapping };
}

/** Pure v2 projection; never infer mappings from old records. */
export function projectMeasuredPhotoModelOutcome(
  ...args: Parameters<typeof projectPhotoModelOutcomeWithMapping>
): { record: PhotoModelMeasurementRecord; display: ReviewDisplay | null } {
  // V1 name lists cannot establish whether a match was canonical or a synonym.
  check(args[7].version === "evaluation_taxonomy_v2");
  const { record, display, mapping } = projectPhotoModelOutcomeWithMapping(
    ...args,
  );
  return {
    record: parsePhotoModelMeasurementRecord(
      { ...record, version: "photo_model_attempt_v2", mapping },
      args[4],
      args[5],
      args[6],
    ),
    display,
  };
}
