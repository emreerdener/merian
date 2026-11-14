/** Explicit test profile for the complimentary Pro fixture, separate from any installed archive. */
import type { LegacyGeminiAttemptSnapshot } from "../../ai/contracts.ts";
import { diagnosticTriggerForTier } from "../../identify/thresholds.ts";
export const syntheticOriginalPhotoSnapshot: LegacyGeminiAttemptSnapshot = {
  task: "identify",
  binding: "gemini_baseline_v1",
  provider: "gemini",
  variant: "vision_compat",
  model: "gemini-2.5-pro",
  contextKind: "user_request",
  operation: "scan_identification",
  policyVersion: 1,
  permission: "google_gemini",
  prompt: "identify_vision_v1",
  schema: "merian_identify_v1",
  confidence: "gemini_vision_compat_v1",
  diagnosticTrigger: diagnosticTriggerForTier("pro"),
  promptDiagnosticTrigger: diagnosticTriggerForTier("pro"),
  safety: "biological_vision_v1",
  timeoutMs: 90000,
  generation: {
    temperature: 0.1,
    seed: 42,
    topK: 40,
    maxOutputTokens: 8192,
    thinkingBudget: 5000,
  },
};
