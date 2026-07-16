import assert from "node:assert/strict";
import test from "node:test";
import {
  compactSpeciesTitle,
  nativeExplorePostUrl,
  postTitle,
} from "./formatting.ts";

test("uses Naturebook for public fallbacks and native routes", () => {
  assert.equal(compactSpeciesTitle("", ""), "Naturebook discovery");
  assert.equal(postTitle(""), "Naturebook discovery");
  assert.equal(
    nativeExplorePostUrl("post-123"),
    "naturebook://explore/post/post-123",
  );
});
