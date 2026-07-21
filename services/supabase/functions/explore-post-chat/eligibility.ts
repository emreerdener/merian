import type { ExplorePostChatContext } from "./types.ts";

export function isExplorePostChatContextAvailable(
  context: ExplorePostChatContext | null,
): context is ExplorePostChatContext {
  return context !== null;
}
