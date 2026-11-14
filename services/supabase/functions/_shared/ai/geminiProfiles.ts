import type { ThinkingLevel } from "@google/genai";

/** Server-owned configuration. Registration never changes product routing. */
export const GEMINI_IDENTIFICATION_MODEL = "gemini-3.8-flash" as const;
export const GEMINI_SUPPORT_MODEL = "gemini-3.5-flash-lite" as const;
export const GEMINI_GENERATION3_BINDING = "gemini_generation3_v1" as const;
export const GEMINI_LEGACY_DISPATCH_CUTOFF = Date.parse("2026-11-30T00:00:00Z");

export const GEMINI_CANDIDATE_PROFILES = Object.freeze(
  {
    identify: {
      model: GEMINI_IDENTIFICATION_MODEL,
      thinkingLevel: "medium",
      maxOutputTokens: 8192,
    },
    field_chat: {
      model: GEMINI_SUPPORT_MODEL,
      thinkingLevel: "low",
      maxOutputTokens: 4096,
    },
    field_notes: {
      model: GEMINI_SUPPORT_MODEL,
      thinkingLevel: "minimal",
      maxOutputTokens: 1024,
    },
    suggested_questions: {
      model: GEMINI_SUPPORT_MODEL,
      thinkingLevel: "minimal",
      maxOutputTokens: 1024,
    },
    species_overview: {
      model: GEMINI_SUPPORT_MODEL,
      thinkingLevel: "minimal",
      maxOutputTokens: 2048,
    },
    lookalikes: {
      model: GEMINI_SUPPORT_MODEL,
      thinkingLevel: "minimal",
      maxOutputTokens: 1024,
    },
    group_tags: {
      model: GEMINI_SUPPORT_MODEL,
      thinkingLevel: "minimal",
      maxOutputTokens: 512,
    },
    discovery_search: {
      model: GEMINI_SUPPORT_MODEL,
      thinkingLevel: "minimal",
      maxOutputTokens: 2048,
    },
    photo_moderation: {
      model: GEMINI_SUPPORT_MODEL,
      thinkingLevel: "minimal",
      maxOutputTokens: 2048,
    },
    audio_moderation: {
      model: GEMINI_SUPPORT_MODEL,
      thinkingLevel: "minimal",
      maxOutputTokens: 4096,
    },
  } as const,
);
for (const profile of Object.values(GEMINI_CANDIDATE_PROFILES)) {
  Object.freeze(profile);
}
export const GEMINI_PROFILE_VERSION = "gemini_generation3_v1";
export const GEMINI_EVALUATION_DESCRIPTOR = Object.freeze({
  version: 1,
  quality: "unmeasured",
  calibration: "unqualified",
  profileVersion: GEMINI_PROFILE_VERSION,
});
export type GeminiCandidateOperation = keyof typeof GEMINI_CANDIDATE_PROFILES;

export function candidateGeneration(operation: GeminiCandidateOperation) {
  const profile = GEMINI_CANDIDATE_PROFILES[operation];
  return {
    maxOutputTokens: profile.maxOutputTokens,
    thinkingConfig: {
      thinkingLevel: profile.thinkingLevel === "medium"
        ? "MEDIUM" as ThinkingLevel
        : profile.thinkingLevel === "low"
        ? "LOW" as ThinkingLevel
        : "MINIMAL" as ThinkingLevel,
    },
  };
}

/** Exact aliases only. No family regex can silently accept provider rerouting. */
export function geminiReturnedModelMatches(
  requested: string,
  returned: string | null,
): boolean {
  return [
    "gemini-2.5-pro",
    "gemini-2.5-flash",
    GEMINI_IDENTIFICATION_MODEL,
    GEMINI_SUPPORT_MODEL,
  ]
    .includes(requested) && requested === returned;
}

export function assertGeminiLegacyDispatchOpen(
  model: string,
  now = Date.now(),
): void {
  if (
    (model === "gemini-2.5-pro" || model === "gemini-2.5-flash") &&
    now >= GEMINI_LEGACY_DISPATCH_CUTOFF
  ) {
    throw new Error("gemini_legacy_dispatch_closed");
  }
}
