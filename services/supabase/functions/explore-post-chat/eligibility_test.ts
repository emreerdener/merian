import { assert, assertFalse } from "@std/assert";
import { isExplorePostChatContextAvailable } from "./eligibility.ts";
import type { ExplorePostChatContext } from "./types.ts";

function contextOwnedByViewer(
  isOwnedByViewer: boolean,
): ExplorePostChatContext {
  return {
    post: { is_owned_by_viewer: isOwnedByViewer },
    detail: {},
  } as ExplorePostChatContext;
}

Deno.test("Explore Field chat accepts visible posts owned by the viewer", () => {
  assert(isExplorePostChatContextAvailable(contextOwnedByViewer(true)));
});

Deno.test("Explore Field chat accepts visible posts owned by another user", () => {
  assert(isExplorePostChatContextAvailable(contextOwnedByViewer(false)));
});

Deno.test("Explore Field chat rejects unavailable posts", () => {
  assertFalse(isExplorePostChatContextAvailable(null));
});
