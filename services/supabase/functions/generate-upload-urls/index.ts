import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  createStagedScanMediaAssets,
  StagedScanMediaAssetInput,
  StagedScanMediaAssetRow,
} from "../_shared/scanMediaAssets.ts";
import { generateStagingUrls, parseStagingUploadFiles } from "./storage.ts";
import type { PresignedUrlPayload, StagingUploadFile } from "./storage.ts";

function stagedAssetInputs(
  userId: string,
  files: StagingUploadFile[],
  urls: PresignedUrlPayload[],
): StagedScanMediaAssetInput[] {
  const sessionIdByClientScanId = new Map<string, string>();

  return files.flatMap((file, index) => {
    if (!file.clientScanId || !file.mediaRole) return [];
    const url = urls[index];
    if (!url) return [];

    const uploadSessionId = sessionIdByClientScanId.get(file.clientScanId) ??
      crypto.randomUUID();
    sessionIdByClientScanId.set(file.clientScanId, uploadSessionId);

    return [{
      userId,
      clientScanId: file.clientScanId,
      uploadSessionId,
      kind: file.mediaKind,
      role: file.mediaRole,
      storageKey: url.objectKey,
      orderIndex: index,
      contentType: file.contentType,
      byteSize: file.sizeBytes ?? null,
      metadata: {
        fileName: file.fileName,
        endpoint: "generate-upload-urls",
      },
    }];
  });
}

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
    let body: unknown;

    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const parsed = parseStagingUploadFiles(body);
    if (parsed.error || !parsed.files) {
      return jsonResponse(
        { error: parsed.error ?? "Invalid upload manifest" },
        parsed.status ?? 400,
      );
    }

    const urls = await generateStagingUrls(user.id, parsed.files);
    const stagedAssets = await createStagedScanMediaAssets(
      stagedAssetInputs(user.id, parsed.files, urls),
      supabaseAdmin,
    );

    return jsonResponse({
      success: true,
      urls: attachStagedAssetIds(urls, stagedAssets),
    }, 200);
  })
);
