import type {
  AIProviderOutcome,
  AIUsage,
} from "../../functions/_shared/ai/contracts.ts";
import type { EvaluationInput, Prediction } from "./contracts.ts";
import { normalizeEvaluationDraft } from "./normalization.ts";
import { confidencePolicy, estimateCost } from "./profiles.ts";
import {
  type Assignment,
  type AttemptRecord,
  parseAttempt,
  type Pricing,
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
export function projectUsage(usage: AIUsage | null): StoredUsage | null {
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
  };
}
export function emptyRecord(
  a: Assignment,
  runDigest: string,
  reason: Reason = "unattempted",
): AttemptRecord {
  return parseAttempt({
    version: "evaluation_attempt_v1",
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
  pricing: Pricing | null,
): AttemptRecord {
  const record = emptyRecord(a, runDigest);
  record.usage = projectUsage(outcome.usage);
  record.providerMs = duration(outcome.providerDurationMs);
  record.returnedModel = typeof outcome.returnedModel === "string" &&
      /^gemini-[a-zA-Z0-9.-]{1,100}$/.test(outcome.returnedModel)
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
      const lookup = (name: string) =>
        taxonomy.taxa.find((t) =>
          t.names.some((n) => n.toLowerCase() === name.toLowerCase())
        )?.taxon ?? null;
      const human = value.is_biological_subject &&
        (normalized.audioSubjectKind === "human" ||
          value.scientific_name?.toLowerCase() === "homo sapiens");
      const subject = human
        ? "human"
        : value.is_biological_subject
        ? "biological"
        : "non_biological";
      const named = subject === "biological" && !!value.scientific_name;
      record.prediction = {
        caseId: a.caseId,
        outcome: "normalized",
        subject,
        resolution: named ? "named" : "unresolved",
        taxon: named ? lookup(value.scientific_name!) : null,
        confidence: value.confidence_score ?? 0,
      } satisfies Prediction;
      const confidence = record.prediction.confidence,
        policy = confidencePolicy(a.profile);
      record.band = confidence >= policy.strong
        ? "strong"
        : confidence >= policy.possible
        ? "possible"
        : "below_possible";
      record.diagnostic = confidence >= policy.diagnostic;
      record.candidates = normalized.clientCandidates?.map((c) => ({
        taxon: lookup(c.scientific_name),
        confidence: c.confidence_score,
      })) ?? null;
      record.normalizationMs = Math.max(0, performance.now() - start);
      record.reason = "completed";
    } catch {
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
