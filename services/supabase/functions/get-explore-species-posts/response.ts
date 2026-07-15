import type { ExploreSpeciesPostRow } from "./db.ts";

export type PublicExploreSpeciesPostRow = Omit<
  ExploreSpeciesPostRow,
  "image_quality_score"
>;

export interface ExploreSpeciesPostCursorPayload {
  image_quality_score: number | null;
  shared_at: string;
  post_id: string;
}

export interface PreparedExploreSpeciesPostsPage {
  data: PublicExploreSpeciesPostRow[];
  nextCursor: ExploreSpeciesPostCursorPayload | null;
}

export function prepareExploreSpeciesPostsPage(
  rows: ExploreSpeciesPostRow[],
  limit: number,
): PreparedExploreSpeciesPostsPage {
  const hasMore = rows.length > limit;
  const pageRows = rows.slice(0, limit);
  const lastRow = pageRows.at(-1);
  const data = pageRows.map((row) => {
    const { image_quality_score: _imageQualityScore, ...post } = row;
    return post;
  });

  return {
    data,
    nextCursor: hasMore && lastRow
      ? {
        image_quality_score: lastRow.image_quality_score,
        shared_at: lastRow.shared_at,
        post_id: lastRow.post_id,
      }
      : null,
  };
}
