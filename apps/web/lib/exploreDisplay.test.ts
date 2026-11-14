import assert from "node:assert/strict";
import { statSync } from "node:fs";
import test from "node:test";
import {
  displayExploreCards,
  explorePostHref,
  explorePreviewCards,
} from "./exploreDisplay.ts";

test("the offline preview uses bundled images and never creates post links", () => {
  assert.equal(explorePreviewCards.length, 48);
  assert.equal(new Set(explorePreviewCards.map((card) => card.id)).size, 48);
  for (const card of explorePreviewCards) {
    assert.ok(card.poster?.startsWith("/assets/hero-nature/"));
    assert.ok(
      statSync(new URL(`../public${card.poster}`, import.meta.url)).size > 0,
    );
    assert.equal(explorePostHref(card, true), undefined);
    assert.equal(explorePostHref(card, false), undefined);
  }
});

test("only a loaded community image can activate its post, not its fallback", () => {
  const card = {
    id: "fixture-observation",
    label: "A public discovery",
    poster: "/api/explore/poster/fixture-observation",
  };
  const [display] = displayExploreCards([card]);
  assert.equal(explorePostHref(display, false), undefined);
  assert.equal(
    explorePostHref(display, true),
    "/explore/post/fixture-observation",
  );
  assert.ok(display.fallbackPoster.startsWith("/assets/hero-nature/"));
  assert.deepEqual(Object.keys(card), ["id", "label", "poster"]);
});

test("unpopulated and loading cells never expose empty space or duplicate public posts", async () => {
  const { canvasDisplayCard } = await import("./exploreDisplay.ts");
  const cards = displayExploreCards([{
    id: "real-post",
    label: "Discovery",
    poster: "/photo.webp",
  }]);
  assert.equal(canvasDisplayCard(cards, 0).id, "real-post");
  const edge = canvasDisplayCard(cards, 9999);
  assert.ok(edge.poster);
  assert.equal(edge.decorative, true);
  assert.equal(explorePostHref(edge, true), undefined);
  assert.equal(canvasDisplayCard([], 9999).placeholder, true);
  assert.notEqual(canvasDisplayCard(cards, 10000).id, edge.id);
});
