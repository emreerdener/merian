import {
  cleanScanMediaAssetRows,
  ScanMediaAssetRow,
} from "./scanMediaAssets.ts";
import {
  canonicalizeCompatibleCapturedMediaWireV1,
  type SerializedMediaItemDTO,
} from "./capturedMediaContract.ts";

export type ExploreComposerMediaKind = "image" | "video" | "audio";

export interface ExploreComposerScanMediaRow {
  id: string;
  image_storage_urls?: string[] | null;
  video_storage_urls?: string[] | null;
  audio_storage_urls?: string[] | null;
  captured_media?: unknown[] | null;
  media_assets?: ScanMediaAssetRow[] | null;
}

export interface ExploreComposerMediaSource {
  source_media_id: string;
  kind: ExploreComposerMediaKind;
  url: string;
  thumbnail_url: string;
  order_index: number;
  has_audio: boolean;
  is_selected?: boolean;
  selection_order_index?: number | null;
}

export interface ExploreSourceMediaId {
  scanId: string;
  kind: ExploreComposerMediaKind;
  index: number;
}

function cleanCredentialFreeHTTPSURL(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  if (normalized.length === 0) return null;
  try {
    const url = new URL(normalized);
    return url.protocol === "https:" && Boolean(url.hostname) &&
        !url.username && !url.password
      ? normalized
      : null;
  } catch {
    return null;
  }
}

export function cleanMediaUrls(value: string[] | null | undefined): string[] {
  return (value ?? []).flatMap((url) => {
    const cleaned = cleanCredentialFreeHTTPSURL(url);
    return cleaned ? [cleaned] : [];
  });
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
    /^scan:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}):(image|video|audio):(\d+)$/i,
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
  const assetRows = buildComposerMediaSourcesFromAssets(
    scan,
    selectedSourceMediaIds,
  );
  if (assetRows.length > 0) {
    return assetRows;
  }

  const imageUrls = cleanMediaUrls(scan.image_storage_urls);
  const videoUrls = cleanMediaUrls(scan.video_storage_urls);
  const audioUrls = cleanMediaUrls(scan.audio_storage_urls);
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
      has_audio: false,
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
      has_audio: false,
      is_selected: selectedSourceMediaIds.has(sourceMediaId),
      selection_order_index: selectedSourceMediaIds.get(sourceMediaId) ?? null,
    });
  });

  audioUrls.forEach((url, index) => {
    const sourceMediaId = makeSourceMediaId(scan.id, "audio", index);
    rows.push({
      source_media_id: sourceMediaId,
      kind: "audio",
      url,
      thumbnail_url: "",
      order_index: rows.length,
      has_audio: true,
      is_selected: selectedSourceMediaIds.has(sourceMediaId),
      selection_order_index: selectedSourceMediaIds.get(sourceMediaId) ?? null,
    });
  });

  return rows;
}

function buildComposerMediaSourcesFromAssets(
  scan: ExploreComposerScanMediaRow,
  selectedSourceMediaIds: Map<string, number>,
): ExploreComposerMediaSource[] {
  const assets = cleanScanMediaAssetRows(scan.media_assets);
  if (assets.length === 0) return [];

  const rows: ExploreComposerMediaSource[] = [];
  let imageIndex = 0;
  let videoIndex = 0;
  let audioIndex = 0;

  for (const asset of assets) {
    const index = asset.kind === "video"
      ? videoIndex
      : asset.kind === "audio"
      ? audioIndex
      : imageIndex;
    const sourceMediaId = makeSourceMediaId(scan.id, asset.kind, index);
    const assetUrl = cleanCredentialFreeHTTPSURL(asset.url);
    const thumbnailUrl = cleanCredentialFreeHTTPSURL(asset.thumbnail_url) ??
      (asset.kind === "image" ? assetUrl ?? "" : "");

    if (!assetUrl) {
      if (asset.kind === "video") videoIndex += 1;
      else if (asset.kind === "audio") audioIndex += 1;
      else imageIndex += 1;
      continue;
    }

    if (asset.kind === "video" && thumbnailUrl.length === 0) {
      videoIndex += 1;
      continue;
    }

    rows.push({
      source_media_id: sourceMediaId,
      kind: asset.kind,
      url: assetUrl,
      thumbnail_url: thumbnailUrl,
      order_index: rows.length,
      has_audio: asset.kind === "audio" ||
        (asset.kind === "video" && asset.has_audio === true),
      is_selected: selectedSourceMediaIds.has(sourceMediaId),
      selection_order_index: selectedSourceMediaIds.get(sourceMediaId) ?? null,
    });

    if (asset.kind === "video") {
      videoIndex += 1;
    } else if (asset.kind === "audio") {
      audioIndex += 1;
    } else {
      imageIndex += 1;
    }
  }

  return rows;
}

function buildComposerMediaSourcesFromManifest(
  scan: ExploreComposerScanMediaRow,
  selectedSourceMediaIds: Map<string, number>,
): ExploreComposerMediaSource[] {
  if (!Array.isArray(scan.captured_media) || scan.captured_media.length === 0) {
    return [];
  }

  let manifest: SerializedMediaItemDTO[];
  try {
    manifest = canonicalizeCompatibleCapturedMediaWireV1(scan.captured_media);
  } catch {
    return [];
  }
  if (manifest.length === 0) return [];

  const rows: ExploreComposerMediaSource[] = [];
  let imageIndex = 0;
  let videoIndex = 0;
  let audioIndex = 0;

  for (const item of manifest) {
    if ("audio" in item) {
      const audioUrl = item.audio._0.path;
      const sourceMediaId = makeSourceMediaId(scan.id, "audio", audioIndex);
      rows.push({
        source_media_id: sourceMediaId,
        kind: "audio",
        url: audioUrl,
        thumbnail_url: "",
        order_index: rows.length,
        has_audio: true,
        is_selected: selectedSourceMediaIds.has(sourceMediaId),
        selection_order_index: selectedSourceMediaIds.get(sourceMediaId) ??
          null,
      });
      audioIndex += 1;
      continue;
    }
    if ("image" in item) {
      const imageUrl = item.image._0.path;
      const sourceMediaId = makeSourceMediaId(scan.id, "image", imageIndex);
      rows.push({
        source_media_id: sourceMediaId,
        kind: "image",
        url: imageUrl,
        thumbnail_url: imageUrl,
        order_index: rows.length,
        has_audio: false,
        is_selected: selectedSourceMediaIds.has(sourceMediaId),
        selection_order_index: selectedSourceMediaIds.get(sourceMediaId) ??
          null,
      });
      imageIndex += 1;
      continue;
    }
    if (!("video" in item)) continue;
    const videoPayload = item.video._0;
    const videoUrl = videoPayload.video.path;
    const thumbnailUrl = videoPayload.thumbnail?.path ?? videoUrl;
    const sourceMediaId = makeSourceMediaId(scan.id, "video", videoIndex);
    rows.push({
      source_media_id: sourceMediaId,
      kind: "video",
      url: videoUrl,
      thumbnail_url: thumbnailUrl,
      order_index: rows.length,
      // Captured Media Wire V1 intentionally omits inference-only companion
      // audio. Only normalized ready asset metadata may prove playback audio.
      has_audio: false,
      is_selected: selectedSourceMediaIds.has(sourceMediaId),
      selection_order_index: selectedSourceMediaIds.get(sourceMediaId) ?? null,
    });
    videoIndex += 1;
  }

  return rows;
}
