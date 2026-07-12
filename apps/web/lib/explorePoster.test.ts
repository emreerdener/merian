import assert from "node:assert/strict";
import test from "node:test";
import { explorePosterUrl } from "./exploreMedia.ts";

const audioItem = {
  kind: "audio",
  thumbnailUrl: "https://media.merian.app/spectrogram.png",
} as const;

test("Explore posters prefer the canonical hero image", () => {
  assert.equal(
    explorePosterUrl({
      heroImageUrl: "https://media.merian.app/photo.webp",
      mediaItems: [audioItem],
    }),
    "https://media.merian.app/photo.webp",
  );
});

test("audio-only Explore posts use the persisted spectrogram", () => {
  assert.equal(
    explorePosterUrl({ heroImageUrl: null, mediaItems: [audioItem] }),
    "https://media.merian.app/spectrogram.png",
  );
});

test("audio-only Explore posts retain the fallback when no spectrogram exists", () => {
  assert.equal(
    explorePosterUrl({
      heroImageUrl: null,
      mediaItems: [{ ...audioItem, thumbnailUrl: null }],
    }),
    null,
  );
});
