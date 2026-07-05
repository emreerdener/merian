import {
  countVideoScanMediaAssets,
  type ScanMediaAssetRow,
} from "../_shared/scanMediaAssets.ts";

export interface ScanStatusMediaCompletenessRow {
  video_storage_urls?: unknown;
  captured_media?: unknown;
  media_assets?: ScanMediaAssetRow[] | null;
}

export function normalizeRequiredVideoCount(value: unknown): number {
  if (value == null) return 0;
  if (!Number.isInteger(value) || (value as number) < 0) {
    throw new Error("required_video_count must be a non-negative integer.");
  }
  return value as number;
}

export function cleanMediaUrls(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => typeof entry === "string" ? entry.trim() : "")
    .filter((entry) => entry.length > 0);
}

export function capturedVideoCount(value: unknown): number {
  if (!Array.isArray(value)) return 0;
  return value.filter((entry) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      return false;
    }
    return Object.hasOwn(entry as Record<string, unknown>, "video");
  }).length;
}

export function hasRequiredVideoMedia(
  row: ScanStatusMediaCompletenessRow | null | undefined,
  requiredVideoCount: number,
): boolean {
  if (requiredVideoCount <= 0) return true;
  const videoUrlCount = cleanMediaUrls(row?.video_storage_urls).length;
  const manifestVideoCount = capturedVideoCount(row?.captured_media);
  const assetVideoCount = countVideoScanMediaAssets(row?.media_assets);
  return videoUrlCount >= requiredVideoCount &&
    Math.max(manifestVideoCount, assetVideoCount) >= requiredVideoCount;
}
