import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import mediaStagingContract from "../../../../docs/contracts/media-staging-upload-manifest.json" with {
  type: "json",
};

import {
  MAX_STAGED_AUDIO_BYTES,
  MAX_STAGED_AUDIO_FILES,
  MAX_STAGED_IMAGE_BYTES,
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
  maxImageBytes: number;
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
  fileNameSafeCharacterPattern: string;
  legacyFileNamesAccepted: boolean;
}

Deno.test("media staging constants match the documented cross-language contract", () => {
  const contract = mediaStagingContract as MediaStagingUploadManifestContract;

  assertEquals(contract.endpoint, "/generate-upload-urls");
  assertEquals(MAX_STAGING_FILES, contract.maxFilesPerRequest);
  assertEquals(MAX_STAGED_IMAGE_BYTES, contract.maxImageBytes);
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
  assertEquals(contract.legacyFileNamesAccepted, true);
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
      },
    ],
  });

  assertEquals(parsed.error, undefined);
  assertEquals(parsed.files?.length, 3);
  assertEquals(parsed.files?.[0].mediaKind, "image");
  assertEquals(parsed.files?.[1].contentType, "audio/wav");
  assertEquals(parsed.files?.[2].mediaKind, "video");
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
