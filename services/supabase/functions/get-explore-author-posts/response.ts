import type { ExploreAuthorPostRow } from "./db.ts";

export interface ExploreAuthorPostCursorPayload {
  before_shared_at: string;
  before_post_id: string;
}

export interface PreparedExploreAuthorPostsPage {
  data: ExploreAuthorPostRow[];
  nextCursor: ExploreAuthorPostCursorPayload | null;
}

export function prepareExploreAuthorPostsPage(
  rows: ExploreAuthorPostRow[],
  limit: number,
): PreparedExploreAuthorPostsPage {
  const normalizedLimit = Math.max(Math.trunc(limit), 0);
  const hasMore = rows.length > normalizedLimit;
  const data = rows.slice(0, normalizedLimit);
  const lastRow = data.at(-1);

  return {
    data,
    nextCursor: hasMore && lastRow
      ? {
        before_shared_at: lastRow.shared_at,
        before_post_id: lastRow.post_id,
      }
      : null,
  };
}
