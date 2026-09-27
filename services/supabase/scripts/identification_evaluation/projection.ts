import { isOpenAIProfile } from "../../functions/_shared/ai/openaiRequest.ts";
import type {
  AIProviderOutcome,
  AIUsage,
} from "../../functions/_shared/ai/contracts.ts";
import type { EvaluationInput, Prediction } from "./contracts.ts";
import { noIdentityMapping, resolveTaxon } from "./taxonomy.ts";
import { normalizeEvaluationDraft } from "./normalization.ts";
import { confidencePolicy, estimateCost } from "./profiles.ts";
import {
  type Assignment,
  type AttemptRecord,
  type EvaluationPricing,
  parseAttempt,
  type Reason,
  type StoredUsage,
  type Taxonomy,
  type TokenModalities,
} from "./runContracts.ts";

const count = (v: unknown): number | null =>
  typeof v === "number" && Number.isSafeInteger(v) && v >= 0 && v <= 100000000
    ? v
    : null;
const duration = (v: unknown): number | null =>
  typeof v === "number" && Number.isFinite(v) && v >= 0 && v <= 1e12 ? v : null;
export function projectUsage(
  usage: AIUsage | null,
  measured = false,
): StoredUsage | null {
  if (!usage) return null;
  let modalities: StoredUsage["modalities"] = null;
  const raw = usage.modalityBreakdown;
  if (
    raw &&
    Object.keys(raw).every((k) =>
      ["prompt", "cached", "candidates", "tool"].includes(k)
    )
  ) {
    const entries: [string, TokenModalities][] = [];
    for (const key of ["prompt", "cached", "candidates", "tool"]) {
      const values = raw[key];
      if (
        !values || typeof values !== "object" || Array.isArray(values) ||
        Object.keys(values).some((k) => !["text", "image", "audio"].includes(k))
      ) break;
      const numbers = values as Record<string, unknown>;
      if (Object.values(numbers).some((v) => count(v) === null)) break;
      entries.push([key, {
        text: count(numbers.text) ?? 0,
        image: count(numbers.image) ?? 0,
        audio: count(numbers.audio) ?? 0,
      }]);
    }
    if (entries.length === 4) {
      modalities = Object.fromEntries(entries) as NonNullable<
        StoredUsage["modalities"]
      >;
    }
  }
  return {
    promptTokens: count(usage.promptTokens),
    candidateTokens: count(usage.candidateTokens),
    totalTokens: count(usage.totalTokens),
    thinkingTokens: count(usage.thinkingTokens),
    cachedTokens: count(usage.cachedTokens),
    toolTokens: count(usage.toolTokens),
    modalities,
    ...(measured ? { cacheWriteTokens: count(usage.cacheWriteTokens) } : {}),
  };
}
export function emptyRecord(
  a: Assignment,
  runDigest: string,
  reason: Reason = "unattempted",
  measured = false,
): AttemptRecord {
  return parseAttempt({
    version: isOpenAIProfile(a.profile) && a.profile !== "openai_gpt_6_sol"
      ? "evaluation_openai_attempt_v3"
      : isOpenAIProfile(a.profile)
      ? measured
        ? "evaluation_openai_attempt_v2"
        : "evaluation_openai_attempt_v1"
      : measured
      ? "evaluation_attempt_v2"
      : "evaluation_attempt_v1",
    ...(measured ? { mapping: null, candidateMappings: null } : {}),
    key: a.key,
    runDigest,
    prediction: {
      caseId: a.caseId,
      outcome: reason === "interrupted_attempt"
        ? "unknown_execution"
        : "unattempted",
    },
    reason,
    returnedModel: null,
    band: null,
    diagnostic: false,
    candidates: null,
    usage: null,
    providerMs: null,
    normalizationMs: null,
    estimatedUpperUsd: null,
  });
}
/** Only this bounded projection can reach the journal; draft and diagnostics die here. */
export function projectOutcome(
  outcome: AIProviderOutcome,
  input: EvaluationInput,
  a: Assignment,
  runDigest: string,
  taxonomy: Taxonomy,
  pricing: EvaluationPricing | null,
): AttemptRecord {
  const measured = taxonomy.version === "evaluation_taxonomy_v2";
  const record = emptyRecord(a, runDigest, "unattempted", measured);
  record.usage = projectUsage(outcome.usage, measured);
  record.providerMs = duration(outcome.providerDurationMs);
  record.returnedModel = typeof outcome.returnedModel === "string" &&
      (isOpenAIProfile(a.profile)
        ? /^gpt-6-sol(?:-[a-zA-Z0-9.-]{1,80})?$/
        : /^gemini-[a-zA-Z0-9.-]{1,100}$/).test(outcome.returnedModel)
    ? outcome.returnedModel
    : null;
  record.estimatedUpperUsd = pricing
    ? estimateCost(pricing, a.model, record.usage)
    : null;
  if (outcome.kind !== "draft") {
    record.prediction = { caseId: a.caseId, outcome: outcome.kind };
    record.reason = outcome.kind;
  } else {
    const start = performance.now();
    try {
      const normalized = normalizeEvaluationDraft(
          outcome.draft,
          input,
          a.profile,
        ),
        value = normalized.identification;
      const human = value.is_biological_subject &&
        (normalized.audioSubjectKind === "human" ||
          value.scientific_name?.toLowerCase() === "homo sapiens");
      const subject = human
        ? "human"
        : value.is_biological_subject
        ? "biological"
        : "non_biological";
      const named = subject === "biological" && !!value.scientific_name;
      const identity = named
        ? resolveTaxon(taxonomy, value.scientific_name!)
        : { taxon: null, mapping: noIdentityMapping() };
      if (measured) record.mapping = identity.mapping;
      record.prediction = {
        caseId: a.caseId,
        outcome: "normalized",
        subject,
        resolution: named ? "named" : "unresolved",
        taxon: identity.taxon,
        confidence: value.confidence_score ?? 0,
      } satisfies Prediction;
      const confidence = record.prediction.confidence,
        policy = confidencePolicy(a.profile);
      record.band = policy === null
        ? "unqualified"
        : confidence >= policy.strong
        ? "strong"
        : confidence >= policy.possible
        ? "possible"
        : "below_possible";
      record.diagnostic = policy !== null && confidence >= policy.diagnostic;
      const candidates = normalized.clientCandidates?.map((c) => ({
        identity: resolveTaxon(taxonomy, c.scientific_name),
        confidence: c.confidence_score,
      })) ?? null;
      record.candidates = candidates?.map((c) => ({
        taxon: c.identity.taxon,
        confidence: c.confidence,
      })) ?? null;
      if (measured) {
        record.candidateMappings = candidates?.map((c) => c.identity.mapping) ??
          null;
      }
      record.normalizationMs = Math.max(0, performance.now() - start);
      record.reason = "completed";
    } catch {
      if (measured) {
        record.mapping = null;
        record.candidateMappings = null;
      }
      record.band = null;
      record.diagnostic = false;
      record.candidates = null;
      record.normalizationMs = null;
      record.prediction = { caseId: a.caseId, outcome: "invalid_output" };
      record.reason = "normalization_failed";
    }
  }
  if (
    pricing && record.returnedModel !== a.model &&
    outcome.kind !== "unknown_execution" &&
    outcome.kind !== "operational_failure"
  ) record.reason = "model_mismatch";
  else if (
    pricing && record.estimatedUpperUsd === null &&
    outcome.kind !== "unknown_execution" &&
    outcome.kind !== "operational_failure"
  ) record.reason = "usage_missing";
  return parseAttempt(record);
}
