import type { ExploreMapPostRow } from "./types.ts";

function nonEmptyString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : null;
}

function mediaPosterUrl(row: ExploreMapPostRow): string | null {
  const mediaItems = row.media_items ?? [];

  for (const kind of ["image", "video"] as const) {
    for (const item of mediaItems) {
      if (item.kind !== kind) continue;
      const thumbnailUrl = nonEmptyString(item.thumbnail_url);
      if (thumbnailUrl) return thumbnailUrl;
      if (kind === "image") {
        const imageUrl = nonEmptyString(item.url);
        if (imageUrl) return imageUrl;
      }
    }
  }

  return null;
}

/**
 * Keeps the map payload compatible with deployed iOS builds that require
 * `hero_image_url` to be a JSON string. Media-only posts remain in the result;
 * newer clients can also use `reference_thumbnail_url` directly.
 */
export function normalizeExploreMapRows(
  rows: ExploreMapPostRow[],
): ExploreMapPostRow[] {
  return rows.map((row) => ({
    ...row,
    hero_image_url: mediaPosterUrl(row) ??
      nonEmptyString(row.hero_image_url) ??
      nonEmptyString(row.reference_thumbnail_url) ??
      "",
    reference_thumbnail_url: nonEmptyString(row.reference_thumbnail_url),
  }));
}
