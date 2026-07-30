import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import mediaStagingContract from "../../../../docs/contracts/media-staging-upload-manifest.json" with {
  type: "json",
};

import {
  MAX_STAGED_AUDIO_BYTES,
  MAX_STAGED_AUDIO_FILES,
  MAX_STAGED_IMAGE_BYTES,
  MAX_STAGED_IMAGE_FILES,
  MAX_STAGED_VIDEO_BYTES,
  MAX_STAGED_VIDEO_FILES,
  MAX_STAGING_FILES,
  parseStagingUploadFiles,
  sanitizeStagingFileName,
  STAGING_ALLOWED_CONTENT_TYPES,
} from "./storage.ts";

interface MediaStagingUploadManifestContract {
  schemaVersion: number;
  endpoint: string;
  maxFilesPerRequest: number;
  minFileBytes: number;
  maxImageBytes: number;
  maxImageFiles: number;
  maxAudioBytes: number;
  maxAudioFiles: number;
  maxVideoBytes: number;
  maxVideoFiles: number;
  imageContentTypes: string[];
  audioContentTypes: string[];
  videoContentTypes: string[];
  canonicalQueuedImageContentType: string;
  canonicalQueuedWavContentType: string;
  canonicalQueuedM4AContentType: string;
  canonicalQueuedVideoContentType: string;
  optionalRequestFields: string[];
  uploadPurposes: string[];
  optionalResponseFields: string[];
  mediaRolesByKind: Record<string, string[]>;
  fileNameSafeCharacterPattern: string;
  fileNamesMustBeUnique: boolean;
  legacyFileNamesAccepted: boolean;
}

Deno.test("media staging constants match the documented cross-language contract", () => {
  const contract = mediaStagingContract as MediaStagingUploadManifestContract;

  assertEquals(contract.endpoint, "/generate-upload-urls");
  assertEquals(contract.schemaVersion, 4);
  assertEquals(contract.minFileBytes, 1);
  assertEquals(MAX_STAGING_FILES, contract.maxFilesPerRequest);
  assertEquals(MAX_STAGED_IMAGE_BYTES, contract.maxImageBytes);
  assertEquals(MAX_STAGED_IMAGE_FILES, contract.maxImageFiles);
  assertEquals(MAX_STAGED_AUDIO_BYTES, contract.maxAudioBytes);
  assertEquals(MAX_STAGED_AUDIO_FILES, contract.maxAudioFiles);
  assertEquals(MAX_STAGED_VIDEO_BYTES, contract.maxVideoBytes);
  assertEquals(MAX_STAGED_VIDEO_FILES, contract.maxVideoFiles);
  assertEquals(
    STAGING_ALLOWED_CONTENT_TYPES.image,
    contract.imageContentTypes,
  );
  assertEquals(
    STAGING_ALLOWED_CONTENT_TYPES.audio,
    contract.audioContentTypes,
  );
  assertEquals(
    STAGING_ALLOWED_CONTENT_TYPES.video,
    contract.videoContentTypes,
  );
  assertEquals(contract.optionalRequestFields, [
    "clientScanId",
    "mediaRole",
    "uploadPurpose",
  ]);
  assertEquals(contract.uploadPurposes, ["scan_share_restore"]);
  assertEquals(contract.optionalResponseFields, [
    "mediaAssetId",
    "mediaSessionId",
  ]);
  assertEquals(contract.mediaRolesByKind.video, ["playback"]);
  assertEquals(contract.mediaRolesByKind.audio, ["audio"]);
  assertEquals(contract.mediaRolesByKind.image, [
    "display",
    "thumbnail",
    "inference_frame",
  ]);
  assertEquals(contract.legacyFileNamesAccepted, true);
  assertEquals(contract.fileNamesMustBeUnique, true);
});

Deno.test("parseStagingUploadFiles accepts structured mixed-media manifests", () => {
  const parsed = parseStagingUploadFiles({
    files: [
      {
        fileName: "scan-1_image.webp",
        mediaKind: "image",
        contentType: "image/webp",
        sizeBytes: 125_000,
      },
      {
        fileName: "scan-1_audio.wav",
        mediaKind: "audio",
        contentType: "audio/wav",
        sizeBytes: 42_000,
      },
      {
        fileName: "scan-1_video.mp4",
        mediaKind: "video",
        contentType: "video/mp4",
        sizeBytes: 840_000,
        clientScanId: "00000000-0000-0000-0000-000000000001",
        mediaRole: "playback",
      },
    ],
  });

  assertEquals(parsed.error, undefined);
  assertEquals(parsed.files?.length, 3);
  assertEquals(parsed.files?.[0].mediaKind, "image");
  assertEquals(parsed.files?.[1].contentType, "audio/wav");
  assertEquals(parsed.files?.[2].mediaKind, "video");
  assertEquals(
    parsed.files?.[2].clientScanId,
    "00000000-0000-0000-0000-000000000001",
  );
  assertEquals(parsed.files?.[2].mediaRole, "playback");
});

Deno.test("parseStagingUploadFiles accepts one video scan signing batch", () => {
  const clientScanId = "00000000-0000-0000-0000-000000000001";
  const parsed = parseStagingUploadFiles({
    files: [
      ...Array.from({ length: 5 }, (_, index) => ({
        fileName: `scan-1_frame-${index}.webp`,
        mediaKind: "image",
        contentType: "image/webp",
        sizeBytes: 125_000,
        clientScanId,
        mediaRole: "display",
      })),
      {
        fileName: "scan-1_video.mp4",
        mediaKind: "video",
        contentType: "video/mp4",
        sizeBytes: 840_000,
        clientScanId,
        mediaRole: "playback",
      },
    ],
  });

  assertEquals(parsed.error, undefined);
  assertEquals(parsed.files?.length, 6);
  assertEquals(
    parsed.files?.filter((file) => file.mediaKind === "image").length,
    5,
  );
  assertEquals(
    parsed.files?.filter((file) => file.mediaKind === "video").length,
    1,
  );
});

Deno.test("parseStagingUploadFiles accepts exact scan-share restore manifests", () => {
  const clientScanId = "00000000-0000-4000-8000-000000000001";
  const parsed = parseStagingUploadFiles({
    files: [
      {
        fileName: `${clientScanId}_explore_restore_0.webp`,
        mediaKind: "image",
        contentType: "image/webp",
        sizeBytes: 125_000,
        clientScanId,
        mediaRole: "display",
        uploadPurpose: "scan_share_restore",
      },
      {
        fileName: `${clientScanId}_explore_restore_video_0.mov`,
        mediaKind: "video",
        contentType: "video/mp4",
        sizeBytes: 840_000,
        clientScanId,
        mediaRole: "playback",
        upload_purpose: "scan_share_restore",
      },
      {
        fileName: `${clientScanId}_explore_restore_audio_0.caf`,
        mediaKind: "audio",
        contentType: "audio/wav",
        sizeBytes: 42_000,
        clientScanId,
        mediaRole: "audio",
        uploadPurpose: "scan_share_restore",
      },
    ],
  });

  assertEquals(parsed.error, undefined);
  assertEquals(
    parsed.files?.map((file) => file.uploadPurpose),
    [
      "scan_share_restore",
      "scan_share_restore",
      "scan_share_restore",
    ],
  );
});

Deno.test("parseStagingUploadFiles rejects spoofed scan-share restore manifests", () => {
  const clientScanId = "00000000-0000-4000-8000-000000000001";
  const base = {
    fileName: `${clientScanId}_explore_restore_0.webp`,
    mediaKind: "image",
    contentType: "image/webp",
    sizeBytes: 125_000,
    clientScanId,
    mediaRole: "display",
    uploadPurpose: "scan_share_restore",
  };
  const invalidFiles = [
    { ...base, uploadPurpose: "unknown_purpose" },
    { ...base, clientScanId: undefined },
    {
      ...base,
      fileName: "00000000-0000-4000-8000-000000000099_explore_restore_0.webp",
    },
    {
      ...base,
      fileName: `${clientScanId}_explore_restore_video_0.mp4`,
    },
    { ...base, mediaRole: "thumbnail" },
    {
      ...base,
      client_scan_id: "00000000-0000-4000-8000-000000000099",
    },
    { ...base, media_role: "thumbnail" },
    { ...base, upload_purpose: "unknown_purpose" },
    { ...base, clientScanId: null, client_scan_id: clientScanId },
    { ...base, mediaRole: null, media_role: "display" },
    {
      ...base,
      uploadPurpose: null,
      upload_purpose: "scan_share_restore",
    },
  ];

  for (const file of invalidFiles) {
    const parsed = parseStagingUploadFiles({ files: [file] });
    assertEquals(parsed.status, 400);
  }
});

Deno.test("parseStagingUploadFiles accepts identical compatibility aliases", () => {
  const clientScanId = "00000000-0000-4000-8000-000000000001";
  const parsed = parseStagingUploadFiles({
    files: [{
      fileName: `${clientScanId}_explore_restore_0.webp`,
      mediaKind: "image",
      contentType: "image/webp",
      sizeBytes: 125_000,
      clientScanId,
      client_scan_id: clientScanId,
      mediaRole: "display",
      media_role: "display",
      uploadPurpose: "scan_share_restore",
      upload_purpose: "scan_share_restore",
    }],
  });

  assertEquals(parsed.error, undefined);
  assertEquals(parsed.files, [{
    fileName: `${clientScanId}_explore_restore_0.webp`,
    mediaKind: "image",
    contentType: "image/webp",
    sizeBytes: 125_000,
    clientScanId,
    mediaRole: "display",
    uploadPurpose: "scan_share_restore",
  }]);
});

Deno.test("parseStagingUploadFiles rejects invalid scan media session metadata", () => {
  const badClientScanId = parseStagingUploadFiles({
    files: [
      {
        fileName: "scan-1_video.mp4",
        mediaKind: "video",
        contentType: "video/mp4",
        sizeBytes: 840_000,
        clientScanId: "not-a-uuid",
        mediaRole: "playback",
      },
    ],
  });

  assertEquals(badClientScanId.status, 400);
  assertEquals(
    badClientScanId.error,
    "Bad Request: clientScanId must be a UUID.",
  );

  const badRole = parseStagingUploadFiles({
    files: [
      {
        fileName: "scan-1_video.mp4",
        mediaKind: "video",
        contentType: "video/mp4",
        sizeBytes: 840_000,
        clientScanId: "00000000-0000-0000-0000-000000000001",
        mediaRole: "display",
      },
    ],
  });

  assertEquals(badRole.status, 400);
  assertEquals(
    badRole.error,
    "Bad Request: mediaRole is not valid for mediaKind.",
  );
});

Deno.test("parseStagingUploadFiles rejects unsanitized structured file names", () => {
  const parsed = parseStagingUploadFiles({
    files: [
      {
        fileName: "../scan image.webp",
        mediaKind: "image",
        contentType: "image/webp",
        sizeBytes: 10,
      },
    ],
  });

  assertEquals(parsed.status, 400);
  assertEquals(
    parsed.error,
    "Bad Request: fileName must already be sanitized.",
  );
});

Deno.test("parseStagingUploadFiles rejects duplicate structured storage keys", () => {
  const parsed = parseStagingUploadFiles({
    files: [
      {
        fileName: "duplicate.webp",
        mediaKind: "image",
        contentType: "image/webp",
        sizeBytes: 10,
      },
      {
        fileName: "duplicate.webp",
        mediaKind: "image",
        contentType: "image/webp",
        sizeBytes: 10,
      },
    ],
  });

  assertEquals(parsed.status, 400);
  assertEquals(
    parsed.error,
    "Bad Request: fileName values must be unique.",
  );
});

Deno.test("parseStagingUploadFiles rejects empty structured media before signing", () => {
  const parsed = parseStagingUploadFiles({
    files: [
      {
        fileName: "empty.webp",
        mediaKind: "image",
        contentType: "image/webp",
        sizeBytes: 0,
      },
    ],
  });

  assertEquals(parsed.status, 400);
  assertEquals(
    parsed.error,
    "Bad Request: sizeBytes must be a positive integer.",
  );
});

Deno.test("parseStagingUploadFiles rejects content type and media kind mismatches", () => {
  const parsed = parseStagingUploadFiles({
    files: [
      {
        fileName: "scan_audio.wav",
        mediaKind: "audio",
        contentType: "image/webp",
        sizeBytes: 10,
      },
    ],
  });

  assertEquals(parsed.status, 400);
  assertEquals(
    parsed.error,
    "Bad Request: contentType is not valid for mediaKind.",
  );
});

Deno.test("parseStagingUploadFiles rejects oversized audio before signing", () => {
  const parsed = parseStagingUploadFiles({
    files: [
      {
        fileName: "scan_audio.wav",
        mediaKind: "audio",
        contentType: "audio/wav",
        sizeBytes: MAX_STAGED_AUDIO_BYTES + 1,
      },
    ],
  });

  assertEquals(parsed.status, 413);
});

Deno.test("parseStagingUploadFiles rejects oversized videos before signing", () => {
  const parsed = parseStagingUploadFiles({
    files: [
      {
        fileName: "scan_video.mp4",
        mediaKind: "video",
        contentType: "video/mp4",
        sizeBytes: MAX_STAGED_VIDEO_BYTES + 1,
      },
    ],
  });

  assertEquals(parsed.status, 413);
});

Deno.test("parseStagingUploadFiles rejects arrays over the signing cap", () => {
  const parsed = parseStagingUploadFiles({
    files: Array.from({ length: MAX_STAGING_FILES + 1 }, (_, index) => ({
      fileName: `scan_${index}.webp`,
      mediaKind: "image",
      contentType: "image/webp",
      sizeBytes: 10,
    })),
  });

  assertEquals(parsed.status, 400);
});

Deno.test("parseStagingUploadFiles reserves the sixth slot for non-image media", () => {
  const structured = parseStagingUploadFiles({
    files: Array.from(
      { length: MAX_STAGED_IMAGE_FILES + 1 },
      (_, index) => ({
        fileName: `still_${index}.webp`,
        mediaKind: "image",
        contentType: "image/webp",
        sizeBytes: 10,
      }),
    ),
  });
  const legacy = parseStagingUploadFiles({
    fileNames: Array.from(
      { length: MAX_STAGED_IMAGE_FILES + 1 },
      (_, index) => `legacy_${index}.webp`,
    ),
  });

  assertEquals(structured.status, 400);
  assertEquals(
    structured.error,
    "Bad Request: too many staged image files.",
  );
  assertEquals(legacy.status, 400);
  assertEquals(
    legacy.error,
    "Bad Request: too many staged image files.",
  );
});

Deno.test("parseStagingUploadFiles keeps legacy fileNames compatible", () => {
  const parsed = parseStagingUploadFiles({
    fileNames: ["scan image.webp", "scan/audio.wav", "scan/video.mp4"],
  });

  assertEquals(parsed.error, undefined);
  assertEquals(parsed.files?.map((file) => file.fileName), [
    sanitizeStagingFileName("scan image.webp"),
    sanitizeStagingFileName("scan/audio.wav"),
    sanitizeStagingFileName("scan/video.mp4"),
  ]);
  assertEquals(parsed.files?.[1].mediaKind, "audio");
  assertEquals(parsed.files?.[1].contentType, "audio/wav");
  assertEquals(parsed.files?.[2].mediaKind, "video");
  assertEquals(parsed.files?.[2].contentType, "video/mp4");
});

Deno.test("parseStagingUploadFiles rejects legacy names that sanitize to one key", () => {
  const parsed = parseStagingUploadFiles({
    fileNames: ["scan image.webp", "scan/image.webp"],
  });

  assertEquals(parsed.status, 400);
  assertEquals(
    parsed.error,
    "Bad Request: fileName values must be unique.",
  );
});
