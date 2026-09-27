import type { AIRequest } from "./contracts.ts";

/** Structural profiles of complete, normalized input, never an HTTP selector. */
export const IDENTIFICATION_INPUT_PROFILES = [
  "description_compat_v1",
  "vision_compat_v1",
  "audio_compat_v1",
  "multimodal_text_v1",
  "multimodal_photo_v1",
  "multimodal_audio_v1",
  "multimodal_photo_audio_v1",
  "multimodal_video_frames_v1",
  "multimodal_video_audio_v1",
] as const;
export type IdentificationInputProfile =
  typeof IDENTIFICATION_INPUT_PROFILES[number];
export function isIdentificationInputProfile(
  value: unknown,
): value is IdentificationInputProfile {
  return IDENTIFICATION_INPUT_PROFILES.some((profile) => profile === value);
}

/** Called before admission and again before preparation. Includes every medium;
 * video means sampled frames and/or extracted audio, never a native video upload. */
export function identificationInputProfile(
  request: AIRequest,
): IdentificationInputProfile {
  if (
    request.task !== "identify" ||
    (request.variant !== "description_compat" &&
      request.variant !== "multimodal" && request.variant !== "vision_compat" &&
      request.variant !== "audio_compat")
  ) throw new Error("ai_unsupported_input");
  if (
    request.variant === "description_compat" && (
      request.evidence.length !== 1 ||
      request.evidence[0].kind !== "text" ||
      request.evidence[0].source !== "description" ||
      request.evidence[0].order !== 0 ||
      typeof request.evidence[0].text !== "string" ||
      !request.evidence[0].text.trim()
    )
  ) throw new Error("ai_unsupported_input");
  if (
    request.variant !== "description_compat" && (
      !request.evidence.some((item) =>
        item.kind !== "text" || item.source === "observation_context"
      ) ||
      request.evidence.some((item, index) =>
        item.order !== index || (
          item.kind === "text"
            ? typeof item.text !== "string"
            : item.kind === "image" || item.kind === "audio"
            ? typeof item.data !== "string" ||
              typeof item.mimeType !== "string" ||
              (item.kind === "audio" && item.mimeType !== "audio/wav")
            : true
        )
      )
    )
  ) throw new Error("ai_unsupported_input");

  if (
    (request.variant === "vision_compat" &&
      (!request.evidence.some((item) => item.kind === "image") ||
        request.evidence.some((item) => item.kind === "audio"))) ||
    (request.variant === "audio_compat" &&
      (request.evidence.filter((item) => item.kind === "audio").length !== 1 ||
        request.evidence.some((item) => item.kind === "image")))
  ) throw new Error("ai_unsupported_input");

  if (request.variant === "description_compat") return "description_compat_v1";
  if (request.variant === "vision_compat") return "vision_compat_v1";
  if (request.variant === "audio_compat") return "audio_compat_v1";
  if (request.variant !== "multimodal") throw new Error("ai_unsupported_input");
  const images = request.evidence.some((item) => item.kind === "image");
  const audio = request.evidence.some((item) => item.kind === "audio");
  const capture = request.capture;
  if (
    typeof capture.hasVideo !== "boolean" ||
    [
      capture.videoClipCount,
      capture.declaredVideoFrameCount,
      capture.videoInferenceFrameCount,
    ].some(
      (count) => !Number.isSafeInteger(count) || count < 0,
    )
  ) throw new Error("ai_unsupported_input");
  const video = capture.hasVideo || capture.videoClipCount > 0 ||
    capture.declaredVideoFrameCount > 0 ||
    capture.videoInferenceFrameCount > 0 ||
    request.evidence.some((item) =>
      item.kind === "image"
        ? item.lineage?.kind === "video_frame"
        : item.kind === "audio" && item.lineage?.kind === "video_audio"
    );
  // Even incomplete legacy video lineage must never qualify as photo-only input.
  if (video) {
    return audio ? "multimodal_video_audio_v1" : "multimodal_video_frames_v1";
  }
  if (images) {
    return audio ? "multimodal_photo_audio_v1" : "multimodal_photo_v1";
  }
  return audio ? "multimodal_audio_v1" : "multimodal_text_v1";
}
