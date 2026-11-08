import { invalidInitialInput } from "./canonical.ts";
import { addInitialDecimals, compareInitialDecimals } from "./decimal.ts";

interface Media {
  kind: "image" | "audio" | "video";
  content_type: string;
  source_content_type: string;
  byte_count: number;
  source_byte_count: number;
  sha256: string;
  source_sha256: string;
  input_index: number | null;
  source_index: number | null;
  clip_index: number | null;
  frame_index: number | null;
  focus_region: null | { x: string; y: string; width: string; height: string };
  transform: string;
  transform_parameters: null | {
    target_sample_rate: number;
    preserve_short_video_context: boolean;
  };
}
export interface InitialInput {
  schema_version: 1;
  route: "identify" | "identify-describe" | "identify-multimodal";
  ordered_descriptions: string[];
  media: Media[];
  owner_timeline: { kind: "description" | "media"; index: number }[];
  capture: {
    has_video: boolean;
    video_clip_count: number;
    declared_video_frame_count: number;
    video_inference_frame_count: number;
  };
  experiment: null | unknown;
}

/** Called only after the closed scalar schema. No trim mutates saved text.
 * Frame/companion inputs belong to their video owner, not separate timeline rows.
 */
export function assertInitialSemantics(
  value: unknown,
): asserts value is InitialInput {
  const input = value as InitialInput;
  const descriptions = input.ordered_descriptions;
  const media = input.media;
  const bytes = new TextEncoder();
  for (const text of descriptions) {
    if (
      !text.trim() || bytes.encode(JSON.stringify(text)).length > 65536 ||
      (input.route !== "identify-describe" && text !== text.trim())
    ) invalidInitialInput();
  }
  const imageTypes = [
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/heic",
    "image/heif",
  ];
  let images = 0,
    audio = 0,
    video = 0,
    frames = 0,
    photos = 0,
    recordings = 0,
    imageBytes = 0,
    sourceImageBytes = 0;
  const ownerIndexes: number[] = [];
  const seenFrames = new Set<number>();
  const videoAudio = new Set<number>();
  media.forEach((item, index) => {
    if (item.kind === "video" || item.clip_index === null) {
      ownerIndexes.push(index);
    }
    if (item.kind !== "image" && item.focus_region !== null) {
      invalidInitialInput();
    }
    if (item.focus_region) {
      const f = item.focus_region;
      if (
        compareInitialDecimals(f.width, "0") <= 0 ||
        compareInitialDecimals(f.height, "0") <= 0 ||
        compareInitialDecimals(addInitialDecimals(f.x, f.width), "1") > 0 ||
        compareInitialDecimals(addInitialDecimals(f.y, f.height), "1") > 0
      ) invalidInitialInput();
    }
    if (item.kind === "image") {
      if (
        !imageTypes.includes(item.content_type) ||
        item.source_content_type !== item.content_type ||
        item.input_index !== images++
      ) invalidInitialInput();
      imageBytes += item.byte_count;
      sourceImageBytes += item.source_byte_count;
      if (item.clip_index !== null) {
        if (
          item.clip_index !== 0 || item.source_index !== null ||
          item.frame_index === null || seenFrames.has(item.frame_index) ||
          item.transform !== "video_frame_v1"
        ) invalidInitialInput();
        seenFrames.add(item.frame_index!);
        frames++;
      } else if (
        item.frame_index !== null || item.source_index !== photos++ ||
        item.transform !== "identity_v1"
      ) invalidInitialInput();
      if (
        item.byte_count !== item.source_byte_count ||
        item.sha256 !== item.source_sha256 || item.transform_parameters !== null
      ) invalidInitialInput();
    } else if (item.kind === "audio") {
      if (
        item.content_type !== "audio/wav" ||
        item.source_content_type !== "audio/wav" ||
        item.input_index !== audio++ || item.frame_index !== null ||
        item.transform !== "initial_audio_v1" || item.byte_count > 2_700_000 ||
        item.source_byte_count > 2_700_000
      ) invalidInitialInput();
      if (
        !item.transform_parameters ||
        item.transform_parameters.preserve_short_video_context !==
          (item.clip_index !== null)
      ) invalidInitialInput();
      if (item.clip_index !== null) {
        if (
          item.clip_index !== 0 || item.source_index !== null ||
          videoAudio.has(item.clip_index)
        ) invalidInitialInput();
        videoAudio.add(item.clip_index);
      } else if (item.source_index !== recordings++) invalidInitialInput();
    } else {
      if (
        item.content_type !== "video/mp4" ||
        item.source_content_type !== "video/mp4" ||
        item.clip_index !== video++ || item.input_index !== null ||
        item.source_index !== null || item.frame_index !== null ||
        item.transform !== "identity_v1" ||
        item.transform_parameters !== null ||
        item.byte_count !== item.source_byte_count ||
        item.sha256 !== item.source_sha256
      ) invalidInitialInput();
    }
  });
  if (
    images > 5 || audio > 2 || video > 1 || imageBytes > 5 * 1024 * 1024 ||
    sourceImageBytes > 5 * 1024 * 1024 ||
    ((frames || videoAudio.size) && video !== 1)
  ) invalidInitialInput();
  const capture = input.capture;
  if (
    capture.has_video !== (video > 0) || capture.video_clip_count !== video ||
    capture.video_inference_frame_count !== frames ||
    capture.declared_video_frame_count < frames ||
    (!video && capture.declared_video_frame_count !== 0)
  ) invalidInitialInput();
  if (
    input.route === "identify-describe" &&
      (media.length || descriptions.length !== 1) ||
    input.route === "identify" &&
      (!images || photos !== images || audio || video ||
        descriptions.length > 1) ||
    input.route === "identify-multimodal" && !images && !audio &&
      !descriptions.length
  ) invalidInitialInput();
  const timeline = input.owner_timeline;
  if (
    timeline.length !== ownerIndexes.length + descriptions.length ||
    timeline.length > 64
  ) invalidInitialInput();
  const seen = new Set<number>();
  let descriptionIndex = 0;
  for (const item of timeline) {
    if (item.kind === "description") {
      if (item.index !== descriptionIndex++) invalidInitialInput();
    } else {
      if (!ownerIndexes.includes(item.index) || seen.has(item.index)) {
        invalidInitialInput();
      }
      seen.add(item.index);
    }
  }
  if (
    descriptionIndex !== descriptions.length ||
    seen.size !== ownerIndexes.length
  ) invalidInitialInput();
}

export function initialInputProfile(input: InitialInput): string {
  if (input.route === "identify") return "vision_compat_v1";
  if (input.route === "identify-describe") return "description_compat_v1";
  const audio = input.media.some((m) => m.kind === "audio");
  if (input.capture.has_video) {
    return audio ? "multimodal_video_audio_v1" : "multimodal_video_frames_v1";
  }
  const images = input.media.some((m) => m.kind === "image");
  return images
    ? audio ? "multimodal_photo_audio_v1" : "multimodal_photo_v1"
    : audio
    ? "multimodal_audio_v1"
    : "multimodal_text_v1";
}
