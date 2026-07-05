import {
  buildComposerMediaSources,
  cleanMediaUrls,
  ExploreComposerMediaKind,
  ExploreComposerMediaSource,
  ExploreComposerScanMediaRow,
  makeSourceMediaId,
  parseSourceMediaId,
} from "./exploreComposerMedia.ts";

export interface ExplorePostMediaSelection {
  kind: ExploreComposerMediaKind;
  source_media_id?: string;
  source_index?: number;
  thumbnail_source_index?: number;
  order_index: number;
}

export interface ExplorePostMediaSnapshotRow {
  kind: ExploreComposerMediaKind;
  url: string;
  thumbnail_url: string;
  order_index: number;
  duration_seconds: number | null;
  has_audio: boolean;
}

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export function buildExplorePostMediaRows(
  scan: ExploreComposerScanMediaRow,
  mediaItems: ExplorePostMediaSelection[] | undefined,
): ExplorePostMediaSnapshotRow[] {
  if (mediaItems !== undefined && mediaItems.length === 0) {
    throw makeHttpError(400, "media_items must include at least one item.");
  }

  const composerSources = buildComposerMediaSources(scan);
  const selectedSources = mediaItems === undefined
    ? composerSources
    : mediaItems
      .slice()
      .sort((lhs, rhs) => lhs.order_index - rhs.order_index)
      .map((item) => sourceForSelection(item, scan, composerSources));

  const rows = selectedSources.map((source, offset) => {
    if (source.kind === "video" && source.thumbnail_url === source.url) {
      throw makeHttpError(409, "Video thumbnail unavailable.");
    }

    return {
      kind: source.kind,
      url: source.url,
      thumbnail_url: source.thumbnail_url,
      order_index: offset,
      duration_seconds: null,
      has_audio: source.kind === "video",
    };
  });

  if (rows.length === 0) {
    throw makeHttpError(409, "This scan no longer has shareable media.");
  }

  return rows;
}

export function sourceMediaIdForPostMedia(
  scan: ExploreComposerScanMediaRow,
  kind: ExploreComposerMediaKind,
  url: string,
): string | null {
  const trimmedUrl = url.trim();
  if (trimmedUrl.length === 0) return null;

  const source = buildComposerMediaSources(scan).find((candidate) =>
    candidate.kind === kind && candidate.url === trimmedUrl
  );
  return source?.source_media_id ?? null;
}

function sourceForSelection(
  item: ExplorePostMediaSelection,
  scan: ExploreComposerScanMediaRow,
  composerSources: ExploreComposerMediaSource[],
): ExploreComposerMediaSource {
  if (item.source_media_id) {
    const parsed = parseSourceMediaId(item.source_media_id);
    if (!parsed || parsed.scanId !== scan.id.toLowerCase()) {
      throw makeHttpError(400, "Selected media does not belong to this scan.");
    }
    if (parsed.kind !== item.kind) {
      throw makeHttpError(
        400,
        "Selected media kind does not match its source.",
      );
    }

    const source = composerSources.find((candidate) =>
      candidate.source_media_id === item.source_media_id &&
      candidate.kind === item.kind
    );
    if (!source) {
      throw makeHttpError(
        400,
        `Selected ${item.kind} media does not belong to this scan.`,
      );
    }

    return source;
  }

  return legacySourceForSelection(item, scan);
}

function legacySourceForSelection(
  item: ExplorePostMediaSelection,
  scan: ExploreComposerScanMediaRow,
): ExploreComposerMediaSource {
  if (item.source_index == null) {
    throw makeHttpError(400, "Selected media requires a source.");
  }

  const sourceIndex = item.source_index;
  const imageUrls = cleanMediaUrls(scan.image_storage_urls);
  const videoUrls = cleanMediaUrls(scan.video_storage_urls);

  if (item.kind === "image") {
    const url = imageUrls[sourceIndex];
    if (!url) {
      throw makeHttpError(
        400,
        "Selected image media does not belong to this scan.",
      );
    }

    return {
      source_media_id: makeSourceMediaId(scan.id, "image", sourceIndex),
      kind: "image",
      url,
      thumbnail_url: url,
      order_index: 0,
    };
  }

  const url = videoUrls[sourceIndex];
  if (!url) {
    throw makeHttpError(
      400,
      "Selected video media does not belong to this scan.",
    );
  }

  const thumbnailIndex = item.thumbnail_source_index ?? Math.min(
    sourceIndex,
    imageUrls.length - 1,
  );
  const thumbnailUrl = imageUrls[thumbnailIndex];
  if (!thumbnailUrl) {
    throw makeHttpError(409, "Video thumbnail unavailable.");
  }

  return {
    source_media_id: makeSourceMediaId(scan.id, "video", sourceIndex),
    kind: "video",
    url,
    thumbnail_url: thumbnailUrl,
    order_index: 0,
  };
}
