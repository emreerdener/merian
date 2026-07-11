export type ScanMediaUrlSource = {
  image_storage_urls?: unknown;
  video_storage_urls?: unknown;
  audio_storage_urls?: unknown;
};

function stringUrls(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) =>
    typeof entry === "string" && entry.trim() ? [entry.trim()] : []
  );
}

/** Returns every durable scan-media URL eligible for coordinated R2 deletion. */
export function collectScanMediaUrls(scan: ScanMediaUrlSource): string[] {
  return [
    ...stringUrls(scan.image_storage_urls),
    ...stringUrls(scan.video_storage_urls),
    ...stringUrls(scan.audio_storage_urls),
  ];
}
