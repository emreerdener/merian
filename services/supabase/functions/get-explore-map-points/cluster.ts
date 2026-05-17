import {
  ExploreMapCluster,
  ExploreMapPointsPayload,
  ExploreMapPostRow,
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
  const buckets = new Map<string, { count: number; latitudeSum: number; longitudeSum: number }>();

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

export function buildExploreMapPayload(
  rows: ExploreMapPostRow[],
  zoomLevel: number,
): ExploreMapPointsPayload {
  const cellSize = clusterCellSize(zoomLevel);
  const visibleCount = rows.length;

  if (cellSize == null && rows.length <= MAX_INDIVIDUAL_POSTS) {
    return {
      mode: "posts",
      visible_count: visibleCount,
      clusters: [],
      posts: rows,
    };
  }

  if (rows.length <= 40) {
    return {
      mode: "posts",
      visible_count: visibleCount,
      clusters: [],
      posts: rows,
    };
  }

  if (cellSize == null) {
    return {
      mode: "posts",
      visible_count: visibleCount,
      clusters: [],
      posts: rows.slice(0, MAX_INDIVIDUAL_POSTS),
    };
  }

  const clusters = buildClusters(rows, cellSize);
  const hasMeaningfulAggregation = clusters.some((cluster) => cluster.post_count > 1);

  if (!hasMeaningfulAggregation && rows.length <= MAX_INDIVIDUAL_POSTS) {
    return {
      mode: "posts",
      visible_count: visibleCount,
      clusters: [],
      posts: rows,
    };
  }

  return {
    mode: "clusters",
    visible_count: visibleCount,
    clusters,
    posts: [],
  };
}
