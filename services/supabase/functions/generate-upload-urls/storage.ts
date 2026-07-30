import { generatePresignedPutUrl, getR2Config } from "../_shared/aws.ts";
import {
  MEDIA_BUDGETS,
  STAGING_ALLOWED_CONTENT_TYPES,
} from "../_shared/mediaBudgets.ts";
import type { StagingMediaKind } from "../_shared/mediaBudgets.ts";
import type { ScanMediaAssetRole } from "../_shared/scanMediaAssets.ts";

export type { StagingMediaKind };
export { STAGING_ALLOWED_CONTENT_TYPES };
export type StagingUploadPurpose = "scan_share_restore";

export const MAX_STAGING_FILES = MEDIA_BUDGETS.maxStagingFiles;
export const MAX_STAGED_IMAGE_BYTES = MEDIA_BUDGETS.maxImageRawBytes;
export const MAX_STAGED_IMAGE_FILES = MEDIA_BUDGETS.maxImageCount;
export const MAX_STAGED_AUDIO_BYTES = MEDIA_BUDGETS.maxAudioRawBytes;
export const MAX_STAGED_AUDIO_FILES = MEDIA_BUDGETS.maxStagedAudioFiles;
export const MAX_STAGED_VIDEO_BYTES = MEDIA_BUDGETS.maxVideoRawBytes;
export const MAX_STAGED_VIDEO_FILES = MEDIA_BUDGETS.maxStagedVideoFiles;

export interface StagingUploadFile {
  fileName: string;
  mediaKind: StagingMediaKind;
  contentType: string;
  sizeBytes?: number;
  clientScanId?: string;
  mediaRole?: ScanMediaAssetRole;
  uploadPurpose?: StagingUploadPurpose;
}

export interface PresignedUrlPayload {
  fileName: string;
  signedUrl: string;
  objectKey: string;
  mediaAssetId?: string;
  mediaSessionId?: string;
}

export interface ParseStagingUploadFilesResult {
  files?: StagingUploadFile[];
  error?: string;
  status?: number;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function sanitizeStagingFileName(fileName: string): string {
  const safe = fileName.replace(/[^a-zA-Z0-9_.-]/g, "_");
  return safe.length > 0 ? safe : "upload";
}

function legacyContentTypeForFileName(fileName: string): string {
  const lower = fileName.toLowerCase();
  if (lower.endsWith(".mp4")) return "video/mp4";
  if (lower.endsWith(".wav")) return "audio/wav";
  if (lower.endsWith(".m4a")) return "audio/mp4";
  return "image/webp";
}

function legacyMediaKindForFileName(fileName: string): StagingMediaKind {
  const lower = fileName.toLowerCase();
  if (lower.endsWith(".mp4")) return "video";
  return lower.endsWith(".wav") || lower.endsWith(".m4a") ? "audio" : "image";
}

function allowedContentTypesForKind(kind: StagingMediaKind): Set<string> {
  return new Set(STAGING_ALLOWED_CONTENT_TYPES[kind]);
}

function defaultMediaRoleForKind(kind: StagingMediaKind): ScanMediaAssetRole {
  if (kind === "video") return "playback";
  if (kind === "audio") return "audio";
  return "display";
}

function mediaRoleAllowedForKind(
  role: ScanMediaAssetRole,
  kind: StagingMediaKind,
): boolean {
  if (kind === "video") return role === "playback";
  if (kind === "audio") return role === "audio";
  return role === "display" || role === "thumbnail" ||
    role === "inference_frame";
}

function defaultMediaRoleForRestore(
  kind: StagingMediaKind,
): ScanMediaAssetRole {
  return defaultMediaRoleForKind(kind);
}

function exactScanShareRestoreFileName(
  fileName: string,
  clientScanId: string,
  mediaKind: StagingMediaKind,
): boolean {
  const escapedScanId = clientScanId.replace(
    /[.*+?^${}()|[\]\\]/g,
    "\\$&",
  );
  const suffix = "[.][A-Za-z0-9]+$";
  switch (mediaKind) {
    case "image":
      return new RegExp(
        `^${escapedScanId}_explore_restore_(?:live|[0-9]+)${suffix}`,
        "i",
      ).test(fileName);
    case "video":
      return new RegExp(
        `^${escapedScanId}_explore_restore_video_[0-9]+${suffix}`,
        "i",
      ).test(fileName);
    case "audio":
      return new RegExp(
        `^${escapedScanId}_explore_restore_audio_[0-9]+${suffix}`,
        "i",
      ).test(fileName);
  }
}

function parseUploadPurpose(
  value: unknown,
): { purpose?: StagingUploadPurpose; error?: string } {
  if (value == null) return {};
  if (value !== "scan_share_restore") {
    return { error: "Bad Request: uploadPurpose is not valid." };
  }
  return { purpose: value };
}

function aliasedRequestValue(
  rawFile: Record<string, unknown>,
  camelCaseKey: string,
  snakeCaseKey: string,
): { value?: unknown; error?: string } {
  const hasCamelCaseValue = Object.prototype.hasOwnProperty.call(
    rawFile,
    camelCaseKey,
  );
  const hasSnakeCaseValue = Object.prototype.hasOwnProperty.call(
    rawFile,
    snakeCaseKey,
  );
  const camelCaseValue = rawFile[camelCaseKey];
  const snakeCaseValue = rawFile[snakeCaseKey];
  if (
    hasCamelCaseValue &&
    hasSnakeCaseValue &&
    camelCaseValue !== snakeCaseValue
  ) {
    return {
      error: `Bad Request: ${camelCaseKey} and ${snakeCaseKey} conflict.`,
    };
  }
  return { value: hasCamelCaseValue ? camelCaseValue : snakeCaseValue };
}

function parseMediaRole(
  value: unknown,
  mediaKind: StagingMediaKind,
): { role?: ScanMediaAssetRole; error?: string } {
  if (value == null) return { role: defaultMediaRoleForKind(mediaKind) };
  if (
    value !== "display" &&
    value !== "playback" &&
    value !== "thumbnail" &&
    value !== "inference_frame" &&
    value !== "audio"
  ) {
    return { error: "Bad Request: mediaRole is not valid." };
  }
  if (!mediaRoleAllowedForKind(value, mediaKind)) {
    return { error: "Bad Request: mediaRole is not valid for mediaKind." };
  }
  return { role: value };
}

function cleanClientScanId(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim().toLowerCase();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
      .test(trimmed)
    ? trimmed
    : undefined;
}

function maxBytesForKind(kind: StagingMediaKind): number {
  if (kind === "audio") return MAX_STAGED_AUDIO_BYTES;
  if (kind === "video") return MAX_STAGED_VIDEO_BYTES;
  return MAX_STAGED_IMAGE_BYTES;
}

function error(status: number, message: string): ParseStagingUploadFilesResult {
  return { status, error: message };
}

function validateStructuredUploadFiles(
  rawFiles: unknown[],
): ParseStagingUploadFilesResult {
  const files: StagingUploadFile[] = [];
  const seenFileNames = new Set<string>();
  let totalImageBytes = 0;
  let imageFileCount = 0;
  let audioFileCount = 0;
  let videoFileCount = 0;

  for (const rawFile of rawFiles) {
    if (!isRecord(rawFile)) {
      return error(400, "Bad Request: each file must be an object.");
    }

    const { fileName, mediaKind, contentType, sizeBytes } = rawFile;
    if (typeof fileName !== "string" || fileName.trim().length === 0) {
      return error(400, "Bad Request: fileName must be a non-empty string.");
    }

    const safeFileName = sanitizeStagingFileName(fileName);
    if (safeFileName !== fileName) {
      return error(400, "Bad Request: fileName must already be sanitized.");
    }
    if (seenFileNames.has(fileName)) {
      return error(400, "Bad Request: fileName values must be unique.");
    }
    seenFileNames.add(fileName);

    if (
      mediaKind !== "image" && mediaKind !== "audio" && mediaKind !== "video"
    ) {
      return error(
        400,
        "Bad Request: mediaKind must be 'image', 'audio', or 'video'.",
      );
    }

    if (
      typeof contentType !== "string" ||
      !allowedContentTypesForKind(mediaKind).has(contentType)
    ) {
      return error(400, "Bad Request: contentType is not valid for mediaKind.");
    }

    const clientScanIdValue = aliasedRequestValue(
      rawFile,
      "clientScanId",
      "client_scan_id",
    );
    if (clientScanIdValue.error) {
      return error(400, clientScanIdValue.error);
    }
    const clientScanId = cleanClientScanId(clientScanIdValue.value);
    if (
      (rawFile.clientScanId != null || rawFile.client_scan_id != null) &&
      !clientScanId
    ) {
      return error(400, "Bad Request: clientScanId must be a UUID.");
    }

    const mediaRoleValue = aliasedRequestValue(
      rawFile,
      "mediaRole",
      "media_role",
    );
    if (mediaRoleValue.error) {
      return error(400, mediaRoleValue.error);
    }
    const roleResult = parseMediaRole(mediaRoleValue.value, mediaKind);
    if (roleResult.error || !roleResult.role) {
      return error(400, roleResult.error ?? "Bad Request: invalid mediaRole.");
    }

    const uploadPurposeValue = aliasedRequestValue(
      rawFile,
      "uploadPurpose",
      "upload_purpose",
    );
    if (uploadPurposeValue.error) {
      return error(400, uploadPurposeValue.error);
    }
    const purposeResult = parseUploadPurpose(uploadPurposeValue.value);
    if (purposeResult.error) {
      return error(400, purposeResult.error);
    }
    if (
      purposeResult.purpose &&
      (
        !clientScanId ||
        roleResult.role !== defaultMediaRoleForRestore(mediaKind) ||
        !exactScanShareRestoreFileName(
          fileName,
          clientScanId,
          mediaKind,
        )
      )
    ) {
      return error(
        400,
        "Bad Request: scan-share restore metadata is inconsistent.",
      );
    }

    if (
      typeof sizeBytes !== "number" ||
      !Number.isInteger(sizeBytes) ||
      sizeBytes <= 0
    ) {
      return error(
        400,
        "Bad Request: sizeBytes must be a positive integer.",
      );
    }

    if (sizeBytes > maxBytesForKind(mediaKind)) {
      return error(
        413,
        "Payload Too Large: staged media exceeds its byte budget.",
      );
    }

    if (mediaKind === "image") {
      imageFileCount += 1;
      if (imageFileCount > MAX_STAGED_IMAGE_FILES) {
        return error(400, "Bad Request: too many staged image files.");
      }
      totalImageBytes += sizeBytes;
      if (totalImageBytes > MAX_STAGED_IMAGE_BYTES) {
        return error(
          413,
          "Payload Too Large: staged images exceed the combined byte budget.",
        );
      }
    } else if (mediaKind === "audio") {
      audioFileCount += 1;
      if (audioFileCount > MAX_STAGED_AUDIO_FILES) {
        return error(400, "Bad Request: too many staged audio files.");
      }
    } else {
      videoFileCount += 1;
      if (videoFileCount > MAX_STAGED_VIDEO_FILES) {
        return error(400, "Bad Request: too many staged video files.");
      }
    }

    files.push({
      fileName,
      mediaKind,
      contentType,
      sizeBytes,
      clientScanId,
      mediaRole: roleResult.role,
      uploadPurpose: purposeResult.purpose,
    });
  }

  return { files };
}

function parseLegacyFileNames(
  fileNames: unknown[],
): ParseStagingUploadFilesResult {
  const files: StagingUploadFile[] = [];
  const seenFileNames = new Set<string>();
  let imageFileCount = 0;
  let audioFileCount = 0;
  let videoFileCount = 0;
  for (const fileName of fileNames) {
    if (typeof fileName !== "string" || fileName.trim().length === 0) {
      return error(
        400,
        "Bad Request: fileNames must contain non-empty strings.",
      );
    }

    const safeFileName = sanitizeStagingFileName(fileName);
    if (seenFileNames.has(safeFileName)) {
      return error(400, "Bad Request: fileName values must be unique.");
    }
    seenFileNames.add(safeFileName);
    const mediaKind = legacyMediaKindForFileName(safeFileName);
    if (mediaKind === "image") {
      imageFileCount += 1;
      if (imageFileCount > MAX_STAGED_IMAGE_FILES) {
        return error(400, "Bad Request: too many staged image files.");
      }
    } else if (mediaKind === "audio") {
      audioFileCount += 1;
      if (audioFileCount > MAX_STAGED_AUDIO_FILES) {
        return error(400, "Bad Request: too many staged audio files.");
      }
    } else {
      videoFileCount += 1;
      if (videoFileCount > MAX_STAGED_VIDEO_FILES) {
        return error(400, "Bad Request: too many staged video files.");
      }
    }
    files.push({
      fileName: safeFileName,
      mediaKind,
      contentType: legacyContentTypeForFileName(safeFileName),
    });
  }

  return { files };
}

export function parseStagingUploadFiles(
  body: unknown,
): ParseStagingUploadFilesResult {
  if (!isRecord(body)) {
    return error(400, "Invalid JSON body");
  }

  if (Array.isArray(body.files)) {
    if (body.files.length === 0 || body.files.length > MAX_STAGING_FILES) {
      return error(
        400,
        `Bad Request: 'files' must be an array of 1 to ${MAX_STAGING_FILES} values.`,
      );
    }
    return validateStructuredUploadFiles(body.files);
  }

  if (Array.isArray(body.fileNames)) {
    if (
      body.fileNames.length === 0 || body.fileNames.length > MAX_STAGING_FILES
    ) {
      return error(
        400,
        `Bad Request: 'fileNames' must be an array of 1 to ${MAX_STAGING_FILES} values.`,
      );
    }
    return parseLegacyFileNames(body.fileNames);
  }

  return error(400, "Bad Request: expected 'files' or legacy 'fileNames'.");
}

export async function generateStagingUrls(
  userId: string,
  files: StagingUploadFile[],
): Promise<PresignedUrlPayload[]> {
  const r2Config = getR2Config();

  const urls = await Promise.all(
    files.map(async (file: StagingUploadFile) => {
      const safeFileName = sanitizeStagingFileName(file.fileName);
      const key = `staging/${userId}/${safeFileName}`;

      return {
        fileName: safeFileName,
        signedUrl: await generatePresignedPutUrl(
          r2Config,
          key,
          86400,
          file.contentType,
        ),
        objectKey: key,
      };
    }),
  );

  return urls;
}
