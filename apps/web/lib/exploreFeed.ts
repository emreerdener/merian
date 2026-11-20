import "server-only";
import { fetchExploreFeedPageRows } from "./explore";
import { exploreGridPosterUrl } from "./exploreMedia";
import { approvedExplorePoster } from "./explorePoster";
import { encodeExploreCursor, type ExploreCursor } from "./exploreCursor";
import type { ExplorePage } from "./exploreCanvas";

export async function fetchExplorePage(
  cursor: ExploreCursor | null = null,
): Promise<ExplorePage> {
  const rows = await fetchExploreFeedPageRows(cursor);
  const visible = rows.slice(0, 48);
  const last = visible.at(-1);
  return {
    items: visible.map(({ post }) => ({
      id: post.postId,
      label: `${post.speciesCommonName || "Shared observation"}${
        post.authorUsername ? ` by @${post.authorUsername}` : ""
      }`,
      poster: approvedExplorePoster(exploreGridPosterUrl(post))
        ? `/api/explore/poster/${post.postId}`
        : null,
    })),
    hasMore: rows.length > 48,
    nextCursor: rows.length > 48 && last
      ? encodeExploreCursor({
        sharedAt: last.sharedAt,
        postId: last.post.postId,
      })
      : null,
  };
}
