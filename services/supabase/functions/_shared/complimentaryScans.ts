export interface FlashFallbackEvidenceShape {
  imageCount: number;
  audioCount: number;
  descriptionCount: number;
  videoCount: number;
}

/**
 * Flash fallback is available only for one non-video evidence item. Context
 * telemetry attached to an image/audio capture does not count as another item;
 * callers pass only user-supplied identification evidence here.
 */
export function isFlashFallbackEligible(
  shape: FlashFallbackEvidenceShape,
): boolean {
  const counts = [
    shape.imageCount,
    shape.audioCount,
    shape.descriptionCount,
    shape.videoCount,
  ];
  if (counts.some((count) => !Number.isSafeInteger(count) || count < 0)) {
    return false;
  }
  return shape.videoCount === 0 &&
    shape.imageCount + shape.audioCount + shape.descriptionCount === 1;
}
