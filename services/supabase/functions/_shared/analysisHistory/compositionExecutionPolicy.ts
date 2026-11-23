import type { AIAttemptSnapshot } from "../ai/contracts.ts";
import type { IdentificationInputProfile } from "../ai/identificationInput.ts";
import { prepareMultimodalResultPolicy } from "../ai/multimodalResultPolicy.ts";
import { diagnosticTriggerForTier } from "../identify/thresholds.ts";
import {
  type CompositionRequest,
  parseCompositionRequestStructure,
} from "./compositionAdmission.ts";
import { invalidHistory } from "./contract.ts";
import type { AnalysisWork } from "./execution.ts";

/** Derive the provider profile from every node, including a video's companion
 * audio. This must agree with the existing materialized-request classifier. */
export function compositionExecutionProfile(input: CompositionRequest) {
  const nodes = input.evidence_manifest.items;
  const hasVideo = nodes.some((node) => node.kind === "video");
  const hasVisualEvidence = nodes.some((node) =>
    node.kind === "image" || node.kind === "video"
  );
  const hasAudioEvidence = nodes.some((node) =>
    node.kind === "audio" ||
    (node.kind === "video" && node.provenance.audio !== null)
  );
  const profile: IdentificationInputProfile = hasVideo
    ? hasAudioEvidence
      ? "multimodal_video_audio_v1"
      : "multimodal_video_frames_v1"
    : hasVisualEvidence
    ? hasAudioEvidence ? "multimodal_photo_audio_v1" : "multimodal_photo_v1"
    : hasAudioEvidence
    ? "multimodal_audio_v1"
    : "multimodal_text_v1";
  const focused = input.schema_version === 6 && nodes.some(
    (node) => node.kind === "image" && node.focus_region !== undefined,
  );
  const prompt = hasVisualEvidence
    ? focused
      ? hasAudioEvidence
        ? "identify_blended_focus_v1"
        : "identify_vision_focus_v1"
      : hasAudioEvidence
      ? "identify_blended_v1"
      : "identify_vision_v1"
    : hasAudioEvidence
    ? "identify_audio_v2"
    : "identify_text_v1";
  return { profile, prompt, hasVisualEvidence, hasAudioEvidence };
}

/** Bind preparation and received output to the same saved composition authority. */
export function assertCompositionExecutionSnapshot(
  work: AnalysisWork,
  snapshot: AIAttemptSnapshot,
) {
  const input = parseCompositionRequestStructure(work.input);
  const { hasAudioEvidence, hasVisualEvidence, profile, prompt } =
    compositionExecutionProfile(input);
  const q = work.quota;
  if (
    !q ||
    q.input_profile !==
      profile ||
    q.provider !== "gemini" ||
    !["gemini_baseline_v1", "gemini_generation3_v1"].includes(
      String(q.binding),
    ) ||
    (q.binding === "gemini_generation3_v1" &&
      input.identification_protocol !== 7) ||
    q.processor_permission !== "google_gemini" || q.attempt_count !== 1 ||
    !Number.isSafeInteger(q.policy_version) ||
    (q.policy_version as number) < 1 ||
    (q.effective_tier !== "free" && q.effective_tier !== "pro") ||
    snapshot.provider !== q.provider || snapshot.binding !== q.binding ||
    q.model !==
      (q.binding === "gemini_generation3_v1"
        ? "gemini-3.8-flash"
        : q.effective_tier === "pro"
        ? "gemini-2.5-pro"
        : "gemini-2.5-flash") ||
    snapshot.model !== q.model || snapshot.policyVersion !== q.policy_version ||
    snapshot.diagnosticTrigger !== diagnosticTriggerForTier(
        q.binding === "gemini_generation3_v1" || q.effective_tier === "pro"
          ? "pro"
          : "flash",
      ) ||
    snapshot.prompt !==
      prompt
  ) return invalidHistory();
  prepareMultimodalResultPolicy(snapshot);
  return { input, hasAudioEvidence, hasVisualEvidence };
}
