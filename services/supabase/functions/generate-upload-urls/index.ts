import {
  jsonResponse,
  logStructuredError,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { parseJsonBody } from "../_shared/http.ts";
import { accountDeletionIsActive } from "../_shared/accountDeletion.ts";
import {
  createStagedScanMediaAssets,
  StagedScanMediaAssetRow,
} from "../_shared/scanMediaAssets.ts";
import { generateStagingUrls, parseStagingUploadFiles } from "./storage.ts";
import type { PresignedUrlPayload } from "./storage.ts";
import { stagedAssetInputs } from "./assetRegistration.ts";

function attachStagedAssetIds(
  urls: PresignedUrlPayload[],
  assets: StagedScanMediaAssetRow[],
): PresignedUrlPayload[] {
  if (assets.length === 0) return urls;

  const assetByStorageKey = new Map(
    assets.map((asset) => [asset.storage_key, asset]),
  );

  return urls.map((url) => {
    const asset = assetByStorageKey.get(url.objectKey);
    if (!asset) return url;
    return {
      ...url,
      mediaAssetId: asset.id,
      mediaSessionId: asset.upload_session_id,
    };
  });
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    if (await accountDeletionIsActive(user.id, supabaseAdmin)) {
      return jsonResponse(
        {
          error: "Account deletion is already in progress.",
          code: "account_deletion_in_progress",
        },
        409,
      );
    }

    const body = await parseJsonBody(req, { limit: "standard" });
    if (body instanceof Response) return body;

    const parsed = parseStagingUploadFiles(body);
    if (parsed.error || !parsed.files) {
      return jsonResponse(
        { error: parsed.error ?? "Invalid upload manifest" },
        parsed.status ?? 400,
      );
    }

    const urls = await generateStagingUrls(user.id, parsed.files);
    let stagedAssets: StagedScanMediaAssetRow[];
    try {
      stagedAssets = await createStagedScanMediaAssets(
        stagedAssetInputs(user.id, parsed.files, urls),
        supabaseAdmin,
      );
    } catch (error) {
      logStructuredError("generate_upload_urls_asset_persistence_failed", {
        user_id: user.id,
        media_kinds: [...new Set(parsed.files.map((file) => file.mediaKind))],
        file_count: parsed.files.length,
        error: error instanceof Error ? error.message : String(error),
      });
      return jsonResponse({
        error: "We couldn’t prepare this media for upload. Please try again.",
      }, 503);
    }

    return jsonResponse({
      success: true,
      urls: attachStagedAssetIds(urls, stagedAssets),
    }, 200);
  })
);
