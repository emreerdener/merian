import { processWavBuffer } from "../_shared/audioProcessing.ts";
import type {
  AudioMediaDescriptor,
  OwnerMediaTimelineValidation,
} from "./capturedMedia.ts";

export { isWavContainer } from "../_shared/audioProcessing.ts";

export function processMultimodalWAV(
  buffer: ArrayBuffer,
  descriptor: AudioMediaDescriptor | undefined,
  ownerTimeline: OwnerMediaTimelineValidation,
): string {
  const validatedVideoCompanion = descriptor?.kind === "video_audio" &&
    ownerTimeline.present && ownerTimeline.error === null &&
    ownerTimeline.timeline.some((item) =>
      item.kind === "video" && item.clipIndex === descriptor.clipIndex
    );
  return processWavBuffer(buffer, undefined, {
    preserveSourceWhenTrimmedTooShort: validatedVideoCompanion,
  }).base64Audio;
}
