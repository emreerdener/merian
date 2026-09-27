export interface FlashFallbackEvidenceShape {
  imageCount: number;
  audioCount: number;
  descriptionCount: number;
  videoCount: number;
}

/**
 * Flash fallback is available only for one non-video evidence item. One optional
 * user description may accompany that item. Video-derived media never qualifies.
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
    ((shape.imageCount + shape.audioCount === 1 &&
      shape.descriptionCount <= 1) ||
      (shape.imageCount + shape.audioCount === 0 &&
        shape.descriptionCount === 1));
}
