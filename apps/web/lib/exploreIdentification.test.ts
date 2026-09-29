import { exploreGridPosterUrl } from "./exploreMedia.ts";
import assert from "node:assert/strict";
import test from "node:test";
import {
  identificationDescription,
  originalIdentificationDescription,
  parseExploreIdentification,
} from "./exploreIdentification.ts";
const original = {
  version: 1,
  rank: "genus",
  label_source: "ai_primary",
  original_rank: "genus",
  original_scientific_name: "Fixtureus",
  original_common_name: null,
};
test("public rank projection preserves old rows and distinguishes selected from original labels", () => {
  assert.equal(parseExploreIdentification(undefined), null);
  assert.equal(
    identificationDescription(parseExploreIdentification(original)),
    "Genus-level identification",
  );
  const selected = parseExploreIdentification({
    ...original,
    rank: "species",
    label_source: "verified_selection",
  });
  assert.equal(
    identificationDescription(selected),
    "Species selected by observer",
  );
  assert.equal(
    originalIdentificationDescription(selected),
    "Original AI identification: Fixtureus (genus)",
  );
  const community = parseExploreIdentification({
    ...original,
    label_source: "community",
  });
  assert.equal(
    identificationDescription(community),
    "Community identification · genus",
  );
});
test("malformed present public labels fail closed rather than downgrade to legacy", () => {
  for (
    const row of [
      { ...original, version: 2 },
      { ...original, rank: "species" },
      { ...original, label_source: "verified_selection" },
      { ...original, original_scientific_name: null },
      { ...original, private_review: {} },
      { ...original, original_rank: null },
    ]
  ) {
    assert.throws(() => parseExploreIdentification(row));
  }
});

test("broader and community labels cannot use a species reference thumbnail", () => {
  const post = {
    heroImageUrl: "https://example.invalid/spectrogram.webp",
    referenceThumbnailUrl: "https://example.invalid/reference.webp",
    mediaItems: [{ kind: "audio" as const, thumbnailUrl: null }],
  };
  assert.equal(exploreGridPosterUrl(post), post.referenceThumbnailUrl);
  for (const rank of ["species", "genus", "family", "unresolved_biological"]) {
    const identification = parseExploreIdentification({
      ...original,
      rank,
      label_source: "community",
    });
    assert.equal(
      exploreGridPosterUrl({ ...post, identification }),
      post.heroImageUrl,
    );
  }
  assert.equal(
    exploreGridPosterUrl({
      ...post,
      identification: parseExploreIdentification(original),
    }),
    post.heroImageUrl,
  );
});
