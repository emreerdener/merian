export type ExploreComposerMediaKind = "image" | "video";

export interface ExploreComposerScanMediaRow {
  id: string;
  image_storage_urls?: string[] | null;
  video_storage_urls?: string[] | null;
  captured_media?: unknown[] | null;
}

export interface ExploreComposerMediaSource {
  source_media_id: string;
  kind: ExploreComposerMediaKind;
  url: string;
  thumbnail_url: string;
  order_index: number;
  is_selected?: boolean;
  selection_order_index?: number | null;
}

export interface ExploreSourceMediaId {
  scanId: string;
  kind: ExploreComposerMediaKind;
  index: number;
}

export function cleanMediaUrls(value: string[] | null | undefined): string[] {
  return (value ?? [])
    .map((url) => typeof url === "string" ? url.trim() : "")
    .filter((url) => url.length > 0);
}

export function makeSourceMediaId(
  scanId: string,
  kind: ExploreComposerMediaKind,
  index: number,
): string {
  return `scan:${scanId}:${kind}:${index}`;
}

export function parseSourceMediaId(value: string): ExploreSourceMediaId | null {
  const match = value.trim().match(
    /^scan:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}):(image|video):(\d+)$/i,
  );
  if (!match) return null;

  const index = Number(match[3]);
  if (!Number.isInteger(index) || index < 0) return null;

  return {
    scanId: match[1].toLowerCase(),
    kind: match[2] as ExploreComposerMediaKind,
    index,
  };
}

export function buildComposerMediaSources(
  scan: ExploreComposerScanMediaRow,
  selectedSourceMediaIds: Map<string, number> = new Map(),
): ExploreComposerMediaSource[] {
  const imageUrls = cleanMediaUrls(scan.image_storage_urls);
  const videoUrls = cleanMediaUrls(scan.video_storage_urls);
  const manifestRows = buildComposerMediaSourcesFromManifest(
    scan,
    selectedSourceMediaIds,
  );
  if (manifestRows.length > 0) {
    return manifestRows;
  }

  const rows: ExploreComposerMediaSource[] = [];
  const expectedVideoFrameCount = videoUrls.length * 5;
  const standaloneImageCount = videoUrls.length > 0
    ? Math.max(imageUrls.length - expectedVideoFrameCount, 0)
    : imageUrls.length;
  const visibleImageUrls = imageUrls.slice(0, standaloneImageCount);
  const videoThumbnailUrls = imageUrls.slice(standaloneImageCount);

  visibleImageUrls.forEach((url, index) => {
    const sourceMediaId = makeSourceMediaId(scan.id, "image", index);
    rows.push({
      source_media_id: sourceMediaId,
      kind: "image",
      url,
      thumbnail_url: url,
      order_index: rows.length,
      is_selected: selectedSourceMediaIds.has(sourceMediaId),
      selection_order_index: selectedSourceMediaIds.get(sourceMediaId) ?? null,
    });
  });

  videoUrls.forEach((url, index) => {
    const thumbnailUrl = videoThumbnailUrls[index * 5] ??
      videoThumbnailUrls[0] ??
      imageUrls[0];
    if (!thumbnailUrl) return;

    const sourceMediaId = makeSourceMediaId(scan.id, "video", index);
    rows.push({
      source_media_id: sourceMediaId,
      kind: "video",
      url,
      thumbnail_url: thumbnailUrl,
      order_index: rows.length,
      is_selected: selectedSourceMediaIds.has(sourceMediaId),
      selection_order_index: selectedSourceMediaIds.get(sourceMediaId) ?? null,
    });
  });

  return rows;
}

function buildComposerMediaSourcesFromManifest(
  scan: ExploreComposerScanMediaRow,
  selectedSourceMediaIds: Map<string, number>,
): ExploreComposerMediaSource[] {
  if (!Array.isArray(scan.captured_media) || scan.captured_media.length === 0) {
    return [];
  }

  const rows: ExploreComposerMediaSource[] = [];
  let imageIndex = 0;
  let videoIndex = 0;

  for (const item of scan.captured_media) {
    if (!item || typeof item !== "object") continue;
    const record = item as Record<string, unknown>;
    const imageUrl = serializedMediaPath(record.image);
    if (imageUrl) {
      const sourceMediaId = makeSourceMediaId(scan.id, "image", imageIndex);
      rows.push({
        source_media_id: sourceMediaId,
        kind: "image",
        url: imageUrl,
        thumbnail_url: imageUrl,
        order_index: rows.length,
        is_selected: selectedSourceMediaIds.has(sourceMediaId),
        selection_order_index: selectedSourceMediaIds.get(sourceMediaId) ??
          null,
      });
      imageIndex += 1;
      continue;
    }

    const videoPayload = associatedPayload(record.video);
    if (!videoPayload) continue;
    const videoUrl = storedReferencePath(videoPayload.video);
    if (!videoUrl) continue;

    const thumbnailUrl = storedReferencePath(videoPayload.thumbnail) ??
      videoUrl;
    const sourceMediaId = makeSourceMediaId(scan.id, "video", videoIndex);
    rows.push({
      source_media_id: sourceMediaId,
      kind: "video",
      url: videoUrl,
      thumbnail_url: thumbnailUrl,
      order_index: rows.length,
      is_selected: selectedSourceMediaIds.has(sourceMediaId),
      selection_order_index: selectedSourceMediaIds.get(sourceMediaId) ?? null,
    });
    videoIndex += 1;
  }

  return rows;
}

function serializedMediaPath(value: unknown): string | null {
  const payload = associatedPayload(value);
  return storedReferencePath(payload);
}

function associatedPayload(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object") return null;
  const record = value as Record<string, unknown>;
  const payload = record._0;
  return payload && typeof payload === "object"
    ? payload as Record<string, unknown>
    : null;
}

function storedReferencePath(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  if (!value || typeof value !== "object") return null;
  const path = (value as Record<string, unknown>).path;
  if (typeof path !== "string") return null;
  const trimmed = path.trim();
  return trimmed.length > 0 ? trimmed : null;
}
