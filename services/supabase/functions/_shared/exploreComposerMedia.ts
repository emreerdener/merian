export type ExploreComposerMediaKind = "image" | "video";

export interface ExploreComposerScanMediaRow {
  id: string;
  image_storage_urls?: string[] | null;
  video_storage_urls?: string[] | null;
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
  const rows: ExploreComposerMediaSource[] = [];

  imageUrls.forEach((url, index) => {
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
    const thumbnailUrl = imageUrls[Math.min(index, imageUrls.length - 1)];
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
