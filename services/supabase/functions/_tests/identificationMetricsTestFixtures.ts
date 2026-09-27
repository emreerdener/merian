import type {
  AIRequest,
  UserRequestAuthority,
} from "../_shared/ai/contracts.ts";
import { identificationInputProfile } from "../_shared/ai/identificationInput.ts";
import { identificationProvenance } from "../_shared/ai/provenance.ts";
import { resolveAIClaim } from "../_shared/ai/registry.ts";

export const metricImage = {
  kind: "image" as const,
  order: 0,
  data: "AQ==",
  mimeType: "image/webp",
  inputIndex: 0,
  lineage: null,
};
export const metricAudio = {
  kind: "audio" as const,
  order: 0,
  data: "AQ==",
  mimeType: "audio/wav" as const,
  inputIndex: 0,
  lineage: null,
};
export const metricCapture = {
  hasVideo: false,
  videoClipCount: 0,
  declaredVideoFrameCount: 0,
  videoInferenceFrameCount: 0,
};
export function recordedMetricProvenance(
  request: AIRequest,
  pro = false,
  comparison?: "B",
) {
  const authority: UserRequestAuthority = {
    kind: "user_request",
    userId: "synthetic-owner",
    permission: "google_gemini",
    operation: request.variant === "audio_compat"
      ? "scan_audio_identification"
      : "scan_identification",
    ...(comparison ? { audioPromptComparison: comparison } : {}),
    reservation: {
      id: "synthetic-reservation",
      requestId: "synthetic-request",
      attemptCount: 1,
      policyVersion: 1,
      model: pro ? "gemini-2.5-pro" : "gemini-2.5-flash",
      tier: { effective_tier: pro ? "pro" : "free" },
      assignment: {
        inputProfile: identificationInputProfile(request),
        provider: "gemini",
        binding: "gemini_baseline_v1",
        permission: "google_gemini",
      },
    },
  };
  return identificationProvenance(resolveAIClaim(request, authority));
}
export function geminiMetricProvenance() {
  return recordedMetricProvenance({
    task: "identify",
    variant: "multimodal",
    evidence: [metricImage],
    capture: metricCapture,
  });
}
export function unqualifiedMetricProvenance() {
  return {
    ...geminiMetricProvenance(),
    provider: "future-provider",
    binding: "future_profile_v1",
    model: "future-model",
  };
}
