import type { SupabaseClient } from "@supabase/supabase-js";
import type { R2Config } from "../_shared/aws.ts";
import type { StagedScanMediaAssetRow } from "../_shared/scanMediaAssets.ts";
import { captureObjectBackendDigest } from "../_shared/captureObjectRetirement.ts";
import type { PresignedUrlPayload, StagingUploadFile } from "./storage.ts";

/** Read the actual signed expiry, never an independently sampled local TTL. */
export function signedCaptureUploadExpiry(
  signed: string,
  key: string,
  config: Pick<R2Config, "endpoint" | "bucketName">,
): string {
  const url = new URL(signed);
  const expected = new URL(`${config.endpoint}/${config.bucketName}/${key}`);
  const dates = url.searchParams.getAll("X-Amz-Date");
  const expiries = url.searchParams.getAll("X-Amz-Expires");
  if (
    url.origin !== expected.origin || url.pathname !== expected.pathname ||
    url.username || url.password || url.hash || dates.length !== 1 ||
    expiries.length !== 1 || !/^[0-9]{8}T[0-9]{6}Z$/.test(dates[0]) ||
    !/^[1-9][0-9]{0,4}$/.test(expiries[0]) || Number(expiries[0]) > 86400
  ) throw new Error("Invalid capture upload capability.");
  const date = dates[0];
  const iso = `${date.slice(0, 4)}-${date.slice(4, 6)}-${date.slice(6, 8)}T${
    date.slice(9, 11)
  }:${date.slice(11, 13)}:${date.slice(13, 15)}.000Z`;
  const issued = Date.parse(iso);
  if (!Number.isFinite(issued) || new Date(issued).toISOString() !== iso) {
    throw new Error("Invalid capture upload date.");
  }
  return new Date(issued + Number(expiries[0]) * 1000).toISOString();
}

export async function registerCaptureUploadCapabilities(
  owner: string,
  files: StagingUploadFile[],
  urls: PresignedUrlPayload[],
  assets: StagedScanMediaAssetRow[],
  config: R2Config,
  client: SupabaseClient,
): Promise<void> {
  if (files.length !== urls.length || files.length < 1 || files.length > 8) {
    throw new Error("Invalid capture upload set.");
  }
  const byKey = new Map(assets.map((asset) => [asset.storage_key, asset]));
  if (
    byKey.size !== assets.length ||
    assets.length !== files.filter((file) => file.clientScanId).length ||
    new Set(urls.map((url) => url.objectKey)).size !== urls.length
  ) throw new Error("Invalid capture upload binding.");
  const objects = urls.map((url, index) => {
    const file = files[index];
    const asset = byKey.get(url.objectKey);
    if (
      file.fileName !== url.fileName ||
      url.objectKey !== `staging/${owner}/${file.fileName}` ||
      Boolean(file.clientScanId) !== Boolean(asset)
    ) throw new Error("Invalid capture upload binding.");
    return {
      object_key: url.objectKey,
      expires_at: signedCaptureUploadExpiry(
        url.signedUrl,
        url.objectKey,
        config,
      ),
      scan_id: file.clientScanId ?? null,
      asset_id: asset?.id ?? null,
      session_id: asset?.upload_session_id ?? null,
    };
  });
  const { data, error } = await client.rpc(
    "register_capture_upload_capabilities",
    {
      p_owner: owner,
      p_backend: await captureObjectBackendDigest(config),
      p_objects: objects,
    },
  );
  if (error || data !== true) {
    throw new Error("Capture upload authority could not be persisted.");
  }
}
