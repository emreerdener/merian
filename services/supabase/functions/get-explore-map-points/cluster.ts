import {
  ExploreMapCategoryCount,
  ExploreMapCluster,
  ExploreMapMediaType,
  ExploreMapMediaTypeCount,
  ExploreMapPointsPayload,
  ExploreMapPostRow,
  ExploreMapSpeciesCategory,
} from "./types.ts";

const MAX_INDIVIDUAL_POSTS = 160;

function normalizedZoomLevel(zoomLevel: number): number {
  if (!Number.isFinite(zoomLevel)) return 0;
  return Math.max(0, Math.min(zoomLevel, 20));
}

function clusterCellSize(zoomLevel: number): number | null {
  const zoom = normalizedZoomLevel(zoomLevel);

  if (zoom >= 11) return null;
  if (zoom >= 9) return 0.04;
  if (zoom >= 7) return 0.08;
  if (zoom >= 5) return 0.18;
  if (zoom >= 3) return 0.45;
  return 1.0;
}

function buildClusters(
  rows: ExploreMapPostRow[],
  cellSize: number,
): ExploreMapCluster[] {
  const buckets = new Map<
    string,
    { count: number; latitudeSum: number; longitudeSum: number }
  >();

  for (const row of rows) {
    const latBucket = Math.floor((row.latitude + 90) / cellSize);
    const lonBucket = Math.floor((row.longitude + 180) / cellSize);
    const key = `${latBucket}:${lonBucket}`;

    const bucket = buckets.get(key) ?? {
      count: 0,
      latitudeSum: 0,
      longitudeSum: 0,
    };

    bucket.count += 1;
    bucket.latitudeSum += row.latitude;
    bucket.longitudeSum += row.longitude;
    buckets.set(key, bucket);
  }

  return Array.from(buckets.entries()).map(([id, bucket]) => ({
    id,
    latitude: bucket.latitudeSum / bucket.count,
    longitude: bucket.longitudeSum / bucket.count,
    post_count: bucket.count,
  }));
}

export function categoryForMapPost(
  row: Pick<ExploreMapPostRow, "taxonomy_kingdom" | "taxonomy_class">,
): ExploreMapSpeciesCategory {
  const kingdom = row.taxonomy_kingdom?.trim().toLowerCase() ?? "";
  const className = row.taxonomy_class?.trim().toLowerCase() ?? "";

  if (kingdom === "plantae") return "plants";
  if (kingdom === "fungi") return "fungi";

  switch (className) {
    case "aves":
      return "birds";
    case "mammalia":
      return "mammals";
    case "reptilia":
    case "squamata":
      return "reptiles";
    case "amphibia":
      return "amphibians";
    case "actinopterygii":
    case "chondrichthyes":
    case "sarcopterygii":
      return "fish";
    case "insecta":
    case "entognatha":
      return "insects";
    case "arachnida":
      return "arachnids";
    default:
      return "other";
  }
}

function buildCategoryCounts(
  rows: ExploreMapPostRow[],
): ExploreMapCategoryCount[] {
  const counts = new Map<ExploreMapSpeciesCategory, number>();

  for (const row of rows) {
    const category = categoryForMapPost(row);
    counts.set(category, (counts.get(category) ?? 0) + 1);
  }

  return Array.from(counts.entries())
    .map(([category, count]) => ({ category, count }))
    .sort((lhs, rhs) =>
      rhs.count - lhs.count || lhs.category.localeCompare(rhs.category)
    );
}

export function mediaTypesForMapPost(
  row: Pick<ExploreMapPostRow, "media_items" | "hero_image_url">,
): ExploreMapMediaType[] {
  const mediaTypes = new Set<ExploreMapMediaType>();
  for (const item of row.media_items ?? []) {
    mediaTypes.add(item.kind);
  }

  if (
    mediaTypes.size === 0 &&
    typeof row.hero_image_url === "string" &&
    row.hero_image_url.trim().length > 0
  ) {
    mediaTypes.add("image");
  }

  return Array.from(mediaTypes);
}

function buildMediaTypeCounts(
  rows: ExploreMapPostRow[],
): ExploreMapMediaTypeCount[] {
  const counts = new Map<ExploreMapMediaType, number>();
  for (const row of rows) {
    for (const mediaType of mediaTypesForMapPost(row)) {
      counts.set(mediaType, (counts.get(mediaType) ?? 0) + 1);
    }
  }

  const sortOrder: ExploreMapMediaType[] = ["image", "video", "audio"];
  return Array.from(counts.entries())
    .map(([media_type, count]) => ({ media_type, count }))
    .sort((lhs, rhs) =>
      sortOrder.indexOf(lhs.media_type) - sortOrder.indexOf(rhs.media_type)
    );
}

function filterRowsByCategory(
  rows: ExploreMapPostRow[],
  categoryFilters: ExploreMapSpeciesCategory[],
): ExploreMapPostRow[] {
  if (categoryFilters.length === 0) return rows;

  const requested = new Set(categoryFilters);
  return rows.filter((row) => requested.has(categoryForMapPost(row)));
}

function filterRowsByMediaType(
  rows: ExploreMapPostRow[],
  mediaTypeFilters: ExploreMapMediaType[],
): ExploreMapPostRow[] {
  if (mediaTypeFilters.length === 0) return rows;

  const requested = new Set(mediaTypeFilters);
  return rows.filter((row) =>
    mediaTypesForMapPost(row).some((mediaType) => requested.has(mediaType))
  );
}

export function buildExploreMapPayload(
  rows: ExploreMapPostRow[],
  zoomLevel: number,
  categoryFilters: ExploreMapSpeciesCategory[] = [],
  mediaTypeFilters: ExploreMapMediaType[] = [],
): ExploreMapPointsPayload {
  const categoryCounts = buildCategoryCounts(
    filterRowsByMediaType(rows, mediaTypeFilters),
  );
  const categoryFilteredRows = filterRowsByCategory(rows, categoryFilters);
  const mediaTypeCounts = buildMediaTypeCounts(categoryFilteredRows);
  rows = filterRowsByMediaType(categoryFilteredRows, mediaTypeFilters);
  const cellSize = clusterCellSize(zoomLevel);
  const visibleCount = rows.length;

  if (cellSize == null && rows.length <= MAX_INDIVIDUAL_POSTS) {
    return {
      mode: "posts",
      visible_count: visibleCount,
      category_counts: categoryCounts,
      media_type_counts: mediaTypeCounts,
      clusters: [],
      posts: rows,
    };
  }

  if (rows.length <= 40) {
    return {
      mode: "posts",
      visible_count: visibleCount,
      category_counts: categoryCounts,
      media_type_counts: mediaTypeCounts,
      clusters: [],
      posts: rows,
    };
  }

  if (cellSize == null) {
    return {
      mode: "posts",
      visible_count: visibleCount,
      category_counts: categoryCounts,
      media_type_counts: mediaTypeCounts,
      clusters: [],
      posts: rows.slice(0, MAX_INDIVIDUAL_POSTS),
    };
  }

  const clusters = buildClusters(rows, cellSize);
  const hasMeaningfulAggregation = clusters.some((cluster) =>
    cluster.post_count > 1
  );

  if (!hasMeaningfulAggregation && rows.length <= MAX_INDIVIDUAL_POSTS) {
    return {
      mode: "posts",
      visible_count: visibleCount,
      category_counts: categoryCounts,
      media_type_counts: mediaTypeCounts,
      clusters: [],
      posts: rows,
    };
  }

  return {
    mode: "clusters",
    visible_count: visibleCount,
    category_counts: categoryCounts,
    media_type_counts: mediaTypeCounts,
    clusters,
    posts: [],
  };
}
