import type { ExplorePostMediaItem, ExploreReferenceImage } from "./explore";

export type ExploreVisualSlide =
  | {
      kind: "image";
      url: string;
      source: ExploreReferenceImage["source"] | null;
    }
  | {
      kind: "video";
      url: string;
      posterUrl: string | null;
    };

export function buildExploreVisualSlides({
  mediaItems,
  heroImageUrl,
  referenceImages,
}: {
  mediaItems: ExplorePostMediaItem[];
  heroImageUrl: string | null;
  referenceImages: ExploreReferenceImage[];
}): ExploreVisualSlide[] {
  const seen = new Set<string>();
  const slides: ExploreVisualSlide[] = [];
  const visualItems = mediaItems
    .filter((item) => item.kind === "image" || item.kind === "video")
    .sort((left, right) => left.orderIndex - right.orderIndex);

  for (const item of visualItems) {
    if (seen.has(item.url)) continue;
    seen.add(item.url);
    slides.push(item.kind === "video"
      ? { kind: "video", url: item.url, posterUrl: item.thumbnailUrl }
      : { kind: "image", url: item.url, source: null });
  }

  if (!slides.length && heroImageUrl && !seen.has(heroImageUrl)) {
    seen.add(heroImageUrl);
    slides.push({ kind: "image", url: heroImageUrl, source: null });
  }

  for (const image of referenceImages) {
    if (seen.has(image.url)) continue;
    seen.add(image.url);
    slides.push({ kind: "image", url: image.url, source: image.source });
  }

  return slides;
}
