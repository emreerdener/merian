import { assertEquals } from "@std/assert";

import { stagedAssetInputs } from "./assetRegistration.ts";
import type { PresignedUrlPayload, StagingUploadFile } from "./storage.ts";

const userId = "00000000-0000-4000-8000-000000000001";
const firstScanId = "00000000-0000-4000-8000-000000000002";
const secondScanId = "00000000-0000-4000-8000-000000000003";

function file(
  fileName: string,
  clientScanId?: string,
): StagingUploadFile {
  return {
    fileName,
    mediaKind: "image",
    mediaRole: "display",
    contentType: "image/webp",
    sizeBytes: 42,
    clientScanId,
  };
}

function url(fileName: string): PresignedUrlPayload {
  return {
    fileName,
    signedUrl: `https://uploads.invalid/${fileName}`,
    objectKey: `staging/${userId}/${fileName}`,
  };
}

Deno.test("stagedAssetInputs uses a stable per-scan index across a mixed batch", () => {
  const files = [
    file("first-a.webp", firstScanId),
    file("second-a.webp", secondScanId),
    file("second-b.webp", secondScanId),
    file("first-b.webp", firstScanId),
  ];
  let sessionIndex = 0;

  const inputs = stagedAssetInputs(
    userId,
    files,
    files.map((item) => url(item.fileName)),
    () => `session-${sessionIndex += 1}`,
  );

  assertEquals(
    inputs.map((input) => ({
      scan: input.clientScanId,
      index: input.orderIndex,
      session: input.uploadSessionId,
    })),
    [
      { scan: firstScanId, index: 0, session: "session-1" },
      { scan: secondScanId, index: 0, session: "session-2" },
      { scan: secondScanId, index: 1, session: "session-2" },
      { scan: firstScanId, index: 1, session: "session-1" },
    ],
  );
});

Deno.test("stagedAssetInputs index is independent of legacy and other-scan files", () => {
  const files = [
    file("legacy-avatar.webp"),
    file("other.webp", firstScanId),
    file("target-a.webp", secondScanId),
    file("target-b.webp", secondScanId),
  ];
  const urls = files.map((item) => url(item.fileName));

  const mixed = stagedAssetInputs(userId, files, urls, () => "mixed-session")
    .filter((input) => input.clientScanId === secondScanId);
  const isolated = stagedAssetInputs(
    userId,
    files.slice(2),
    urls.slice(2),
    () => "isolated-session",
  );

  assertEquals(mixed.map((input) => input.orderIndex), [0, 1]);
  assertEquals(isolated.map((input) => input.orderIndex), [0, 1]);
  assertEquals(mixed.map((input) => input.storageKey), [
    `staging/${userId}/target-a.webp`,
    `staging/${userId}/target-b.webp`,
  ]);
});

Deno.test("stagedAssetInputs preserves scan-share restore authorization metadata", () => {
  const restoreFile = {
    ...file(`${firstScanId}_explore_restore_0.webp`, firstScanId),
    uploadPurpose: "scan_share_restore" as const,
  };
  const [input] = stagedAssetInputs(
    userId,
    [restoreFile],
    [url(restoreFile.fileName)],
    () => "restore-session",
  );

  assertEquals(input.uploadPurpose, "scan_share_restore");
  assertEquals(input.metadata, {
    fileName: restoreFile.fileName,
    endpoint: "generate-upload-urls",
    uploadPurpose: "scan_share_restore",
  });
});
