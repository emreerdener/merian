import assert from "node:assert/strict";
import test from "node:test";
import type { ExplorePostMediaItem } from "./explore.ts";
import { buildExploreVisualSlides } from "./exploreVisualMedia.ts";

function media(
  kind: ExplorePostMediaItem["kind"],
  url: string,
  orderIndex: number,
  thumbnailUrl: string | null = null,
): ExplorePostMediaItem {
  return { kind, url, orderIndex, thumbnailUrl, durationSeconds: null, hasAudio: false };
}

test("orders image, audio, and video media canonically", () => {
  const slides = buildExploreVisualSlides({
    mediaItems: [
      media("video", "https://media.merian.app/video.mp4", 2, "https://media.merian.app/poster.webp"),
      media("audio", "https://media.merian.app/audio.wav", 1),
      media("image", "https://media.merian.app/image.webp", 0),
    ],
    heroImageUrl: "https://media.merian.app/unused-hero.webp",
    referenceImages: [],
  });

  assert.deepEqual(slides, [
    { kind: "image", url: "https://media.merian.app/image.webp", source: null },
    {
      kind: "audio",
      url: "https://media.merian.app/audio.wav",
      spectrogramUrl: null,
    },
    {
      kind: "video",
      url: "https://media.merian.app/video.mp4",
      posterUrl: "https://media.merian.app/poster.webp",
    },
  ]);
});

test("uses audio as primary media instead of replacing it with the hero", () => {
  assert.deepEqual(buildExploreVisualSlides({
    mediaItems: [media("audio", "https://media.merian.app/audio.wav", 0)],
    heroImageUrl: "https://media.merian.app/hero.webp",
    referenceImages: [],
  }), [{
    kind: "audio",
    url: "https://media.merian.app/audio.wav",
    spectrogramUrl: null,
  }]);
});

test("appends references and removes duplicate URLs", () => {
  assert.deepEqual(buildExploreVisualSlides({
    mediaItems: [
      media("image", "https://media.merian.app/photo.webp", 0),
      media("image", "https://media.merian.app/photo.webp", 1),
    ],
    heroImageUrl: "https://media.merian.app/photo.webp",
    referenceImages: [
      { url: "https://media.merian.app/photo.webp", source: "Naturebook" },
      { url: "https://wikipedia.org/reference.webp", source: "Wikipedia" },
    ],
  }), [
    { kind: "image", url: "https://media.merian.app/photo.webp", source: null },
    { kind: "image", url: "https://wikipedia.org/reference.webp", source: "Wikipedia" },
  ]);
});
