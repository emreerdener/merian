import type {
  MultimodalAIRequest,
  UserRequestAuthority,
} from "../../functions/_shared/ai/contracts.ts";
import { buildGeminiRequestParameters } from "../../functions/_shared/ai/geminiRequest.ts";
import { resolveAIClaim } from "../../functions/_shared/ai/registry.ts";
import * as thresholds from "../../functions/_shared/identify/thresholds.ts";
import type { EvaluationInput, Profile } from "./contracts.ts";
import { fingerprintEvidence, fingerprintJson } from "./evidence.ts";
import type { Assignment, Pricing, StoredUsage } from "./runContracts.ts";

/** Scripts-only test authority. Never admission, consent or quota evidence. */
export function fixtureAuthority(profile: Profile): UserRequestAuthority {
  return {
    kind: "user_request",
    userId: "synthetic-evaluation",
    permission: "google_gemini",
    operation: "scan_identification",
    reservation: {
      id: "synthetic-reservation",
      requestId: "synthetic-request",
      attemptCount: 1,
      policyVersion: 1,
      model: profile === "gemini_pro" ? "gemini-2.5-pro" : "gemini-2.5-flash",
      tier: { effective_tier: profile === "gemini_pro" ? "pro" : "free" },
    },
  };
}
export function confidencePolicy(profile: Profile) {
  return profile === "gemini_pro"
    ? {
      possible: thresholds.PRO_POSSIBLE,
      strong: thresholds.PRO_STRONG,
      diagnostic: thresholds.PRO_DIAGNOSTIC_TRIGGER,
    }
    : {
      possible: thresholds.FLASH_POSSIBLE,
      strong: thresholds.FLASH_STRONG,
      diagnostic: thresholds.FLASH_DIAGNOSTIC_TRIGGER,
    };
}
export function modelPricing(pricing: Pricing, model: string) {
  const value = pricing.models.find((p) => p.model === model);
  if (!value) throw new Error("evaluation_price_missing");
  return value;
}
/** Worst-case reviewed model ceilings, not a heuristic bytes-to-tokens guess. */
export function reserveCost(pricing: Pricing, model: string): number {
  const p = modelPricing(pricing, model);
  return (p.maxInputTokens * Math.max(...Object.values(p.inputPerMillion)) +
    p.maxBillableOutputTokens *
      Math.max(p.outputPerMillion, ...Object.values(p.inputPerMillion))) / 1e6;
}
/** Conservative upper estimate: all input at the highest rate, no cache discount.
 * Explicit thoughts are included; absent/contradictory billable usage stays unknown.
 */
export function estimateCost(
  pricing: Pricing,
  model: string,
  u: StoredUsage | null,
): number | null {
  if (
    !u || u.promptTokens === null || u.candidateTokens === null ||
    u.thinkingTokens === null || u.totalTokens === null ||
    (u.toolTokens ?? 0) !== 0
  ) return null;
  const p = modelPricing(pricing, model);
  const output = u.candidateTokens + u.thinkingTokens;
  if (
    u.totalTokens < u.promptTokens + output ||
    (u.cachedTokens ?? 0) > u.promptTokens ||
    u.promptTokens > p.maxInputTokens ||
    u.totalTokens - u.promptTokens > p.maxBillableOutputTokens ||
    output > p.maxBillableOutputTokens
  ) return null;
  // Total can include additional billable tokens; conservatively charge all
  // tokens not accounted for as prompt at the output rate as well.
  return (u.promptTokens * Math.max(...Object.values(p.inputPerMillion)) +
    (u.totalTokens - u.promptTokens) *
      Math.max(p.outputPerMillion, ...Object.values(p.inputPerMillion))) / 1e6;
}
export async function assignmentFor(
  input: EvaluationInput,
  request: MultimodalAIRequest,
  profile: Profile,
  attempt: number,
  pricing: Pricing | null,
): Promise<Assignment> {
  const snapshot = resolveAIClaim(request, fixtureAuthority(profile));
  const native = buildGeminiRequestParameters(request, snapshot);
  return {
    key: `${input.caseId}-${profile}-${attempt}`,
    caseId: input.caseId,
    profile,
    attempt,
    inputDigest: await fingerprintEvidence(input),
    requestDigest: await fingerprintJson(native),
    policyDigest: await fingerprintJson(snapshot),
    promptDigest: await fingerprintJson(native.config!.systemInstruction),
    schemaDigest: await fingerprintJson(native.config!.responseSchema),
    confidenceDigest: await fingerprintJson(confidencePolicy(profile)),
    model: snapshot.model,
    prompt: snapshot.prompt,
    schema: snapshot.schema,
    confidence: snapshot.confidence!,
    timeoutMs: snapshot.timeoutMs,
    generation: {
      temperature: snapshot.generation.temperature,
      maxOutputTokens: snapshot.generation.maxOutputTokens,
      seed: snapshot.generation.seed!,
      thinkingBudget: snapshot.generation.thinkingBudget ?? null,
    },
    reservedUsd: pricing ? reserveCost(pricing, snapshot.model) : 0,
  };
}
export function random(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(1664525, state) + 1013904223) >>> 0;
    return state / 4294967296;
  };
}
/** Freeze shuffled case order, then alternate which profile goes first. */
export function interleave(
  assignments: Assignment[],
  seed: number,
): Assignment[] {
  const rng = random(seed),
    ids = [...new Set(assignments.map((a) => a.caseId))].sort();
  for (let i = ids.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [ids[i], ids[j]] = [ids[j], ids[i]];
  }
  const order: Assignment[] = [];
  for (
    let attempt = 1;
    attempt <= Math.max(...assignments.map((a) => a.attempt));
    attempt++
  ) {
    ids.forEach((id, index) => {
      const entries = assignments.filter((a) =>
        a.caseId === id && a.attempt === attempt
      ).sort((a, b) => a.profile.localeCompare(b.profile));
      if ((index + attempt) % 2 === 0) entries.reverse();
      order.push(...entries);
    });
  }
  return order;
}
