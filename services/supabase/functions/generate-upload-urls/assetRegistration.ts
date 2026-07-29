import type { StagedScanMediaAssetInput } from "../_shared/scanMediaAssets.ts";
import type { PresignedUrlPayload, StagingUploadFile } from "./storage.ts";

export function stagedAssetInputs(
  userId: string,
  files: StagingUploadFile[],
  urls: PresignedUrlPayload[],
  randomUUID: () => string = () => crypto.randomUUID(),
): StagedScanMediaAssetInput[] {
  const sessionIdByClientScanId = new Map<string, string>();
  const nextOrderIndexByClientScanId = new Map<string, number>();

  return files.flatMap((file, flatIndex) => {
    if (!file.clientScanId || !file.mediaRole) return [];
    const url = urls[flatIndex];
    if (!url) return [];

    const uploadSessionId = sessionIdByClientScanId.get(file.clientScanId) ??
      randomUUID();
    sessionIdByClientScanId.set(file.clientScanId, uploadSessionId);
    const orderIndex = nextOrderIndexByClientScanId.get(file.clientScanId) ?? 0;
    nextOrderIndexByClientScanId.set(file.clientScanId, orderIndex + 1);

    return [{
      userId,
      clientScanId: file.clientScanId,
      uploadSessionId,
      kind: file.mediaKind,
      role: file.mediaRole,
      storageKey: url.objectKey,
      orderIndex,
      contentType: file.contentType,
      byteSize: file.sizeBytes ?? null,
      uploadPurpose: file.uploadPurpose,
      metadata: {
        fileName: file.fileName,
        endpoint: "generate-upload-urls",
        ...(file.uploadPurpose ? { uploadPurpose: file.uploadPurpose } : {}),
      },
    }];
  });
}
