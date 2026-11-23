import { processWavBuffer } from "../_shared/audioProcessing.ts";
import { decodeBase64 } from "../_shared/encoding.ts";
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
  return processMultimodalAudio(buffer, descriptor, ownerTimeline).base64Audio;
}

/** One DSP result shared by provider dispatch and private evidence retention.
 * The immutable encoded value owns the bytes. Each retention read receives an
 * isolated decode; a caller cannot mutate later reads or trigger DSP again.
 */
export function processMultimodalAudio(
  buffer: ArrayBuffer,
  descriptor: AudioMediaDescriptor | undefined,
  ownerTimeline: OwnerMediaTimelineValidation,
) {
  const validatedVideoCompanion = descriptor?.kind === "video_audio" &&
    ownerTimeline.present && ownerTimeline.error === null &&
    ownerTimeline.timeline.some((item) =>
      item.kind === "video" && item.clipIndex === descriptor.clipIndex
    );
  const base64Audio = processWavBuffer(buffer, undefined, {
    preserveSourceWhenTrimmedTooShort: validatedVideoCompanion,
  }).base64Audio;
  return Object.freeze({
    base64Audio,
    readBytes: (): Uint8Array => decodeBase64(base64Audio),
  });
}
