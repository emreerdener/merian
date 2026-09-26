import type {
  AIAttemptSnapshot,
  AIExecutionAuthority,
  AIRequest,
} from "./contracts.ts";
import { isIdentificationProviderAssignment } from "./admission.ts";
import { identificationInputProfile } from "./identificationInput.ts";
import { diagnosticTriggerForTier } from "../identify/thresholds.ts";
import { resolveContentClaim } from "./contentRegistry.ts";

/** Static server policy: no environment/client provider, model or URL override. */
export function resolveAIClaim(
  request: AIRequest,
  authority: AIExecutionAuthority,
): AIAttemptSnapshot {
  if (
    authority.kind === "user_request" &&
    authority.audioPromptComparison !== undefined
  ) {
    if (
      !["A", "B"].includes(authority.audioPromptComparison) ||
      request.task !== "identify" || request.variant !== "multimodal" ||
      authority.reservation.model !== "gemini-2.5-pro" ||
      authority.reservation.tier?.effective_tier !== "pro" ||
      authority.reservation.attemptCount !== 1 ||
      request.capture.hasVideo || request.capture.videoClipCount !== 0 ||
      request.capture.declaredVideoFrameCount !== 0 ||
      request.capture.videoInferenceFrameCount !== 0 ||
      request.evidence.length !== 2 || request.evidence[0].kind !== "audio" ||
      request.evidence[1].kind !== "text" ||
      request.evidence[1].source !== "capture_context"
    ) throw new Error("ai_audio_prompt_authority_mismatch");
  }
  if (request.task !== "identify") {
    return resolveContentClaim(request, authority);
  }
  const inputProfile = identificationInputProfile(request);

  const operation = request.variant === "audio_compat"
    ? "scan_audio_identification"
    : "scan_identification";
  if (
    authority.kind !== "user_request" ||
    authority.operation !== operation ||
    authority.permission !== "google_gemini" ||
    !isIdentificationProviderAssignment(authority.reservation.assignment) ||
    authority.permission !== authority.reservation.assignment.permission ||
    authority.reservation.assignment.inputProfile !== inputProfile ||
    !authority.userId ||
    !authority.reservation.id || !authority.reservation.requestId ||
    !Number.isSafeInteger(authority.reservation.attemptCount) ||
    authority.reservation.attemptCount < 1 ||
    !Number.isSafeInteger(authority.reservation.policyVersion) ||
    authority.reservation.policyVersion < 1
  ) throw new Error("ai_authority_mismatch");

  const { model, policyVersion } = authority.reservation;
  if (model !== "gemini-2.5-flash" && model !== "gemini-2.5-pro") {
    throw new Error("ai_model_not_enabled");
  }
  const pro = model === "gemini-2.5-pro";
  if (request.variant === "audio_compat") {
    return Object.freeze({
      provider: "gemini",
      binding: "gemini_baseline_v1",
      task: "identify",
      variant: "audio_compat",
      model,
      contextKind: "user_request",
      operation,
      policyVersion,
      permission: "google_gemini",
      prompt: "identify_audio_compat_v2",
      schema: "merian_audio_v2",
      confidence: "gemini_audio_compat_v2",
      timeoutMs: 90000,
      generation: Object.freeze({
        temperature: 0.1,
        seed: 42,
        maxOutputTokens: 2048,
        thinkingBudget: 2048,
      }),
    });
  }
  if (request.variant === "vision_compat") {
    const tier = authority.reservation.tier?.effective_tier;
    if (tier !== "free" && tier !== "pro") {
      throw new Error("ai_authority_mismatch");
    }
    return Object.freeze({
      provider: "gemini",
      binding: "gemini_baseline_v1",
      task: "identify",
      variant: "vision_compat",
      model,
      contextKind: "user_request",
      operation,
      policyVersion,
      permission: "google_gemini",
      prompt: "identify_vision_v1",
      schema: "merian_identify_v1",
      confidence: "gemini_vision_compat_v1",
      diagnosticTrigger: diagnosticTriggerForTier(
        tier === "pro" ? "pro" : "flash",
      ),
      promptDiagnosticTrigger: diagnosticTriggerForTier(pro ? "pro" : "flash"),
      safety: "biological_vision_v1",
      timeoutMs: 90000,
      generation: Object.freeze({
        temperature: 0.1,
        seed: 42,
        topK: 40,
        maxOutputTokens: pro ? 8192 : 4096,
        thinkingBudget: pro ? 5000 : 2048,
      }),
    });
  }
  if (request.variant === "multimodal") {
    const tier = authority.reservation.tier?.effective_tier;
    if (tier !== "free" && tier !== "pro") {
      throw new Error("ai_authority_mismatch");
    }
    const images = request.evidence.some((item) => item.kind === "image");
    const audio = request.evidence.some((item) => item.kind === "audio");
    return Object.freeze({
      provider: "gemini",
      binding: "gemini_baseline_v1",
      task: "identify",
      variant: "multimodal",
      model,
      contextKind: "user_request",
      operation: "scan_identification",
      policyVersion,
      permission: "google_gemini",
      prompt: images
        ? audio ? "identify_blended_v1" : "identify_vision_v1"
        : audio
        ? authority.audioPromptComparison === "B"
          ? "identify_audio_uncertainty_experiment_v1"
          : "identify_audio_v2"
        : "identify_text_v1",
      schema: !images && audio ? "merian_audio_v2" : "merian_identify_v1",
      confidence: !images && audio ? "gemini_audio_v2" : "gemini_identify_v1",
      diagnosticTrigger: diagnosticTriggerForTier(
        tier === "pro" ? "pro" : "flash",
      ),
      timeoutMs: 90000,
      generation: Object.freeze({
        temperature: 0.1,
        seed: 42,
        maxOutputTokens: 8192,
        ...(tier === "pro" ? { thinkingBudget: 5000 as const } : {}),
      }),
    });
  }
  return Object.freeze({
    provider: "gemini",
    binding: "gemini_baseline_v1",
    task: "identify",
    variant: "description_compat",
    model,
    contextKind: "user_request",
    operation: "scan_identification",
    policyVersion,
    permission: "google_gemini",
    prompt: "identify_describe_v1",
    schema: "merian_describe_v1",
    confidence: "gemini_describe_v1",
    timeoutMs: 90000,
    generation: Object.freeze({
      temperature: 0.15,
      seed: 42,
      topK: 40,
      maxOutputTokens: pro ? 4096 : 2048,
      thinkingBudget: pro ? 3000 : 1024,
    }),
  });
}
