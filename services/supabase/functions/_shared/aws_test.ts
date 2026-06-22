import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import r2Lifecycle from "../../../../docs/r2-lifecycle.json" with {
  type: "json",
};
import {
  avatarR2KeyFromPublicUrl,
  deleteR2Objects,
  deleteScanMediaR2Objects,
  isScanMediaR2Url,
  R2_MEDIA_PREFIXES,
  type R2Config,
} from "./aws.ts";

Deno.test("deleteR2Objects caps in-flight deletes and rewrites public media URLs", async () => {
  let inFlight = 0;
  let maxInFlight = 0;
  const deletedUrls: string[] = [];

  const config = {
    bucketName: "media-bucket",
    endpoint: "https://account.r2.cloudflarestorage.com",
    s3Client: {
      async fetch(request: Request | string) {
        inFlight += 1;
        maxInFlight = Math.max(maxInFlight, inFlight);
        const url = request instanceof Request ? request.url : request;
        deletedUrls.push(url);
        assertEquals(
          request instanceof Request ? request.method : "DELETE",
          "DELETE",
        );
        await new Promise((resolve) => setTimeout(resolve, 5));
        inFlight -= 1;
        return new Response(null, { status: 204 });
      },
    },
  } as unknown as R2Config;

  const urls = Array.from(
    { length: 40 },
    (_, index) => `https://media.merian.app/public_uploads/free/${index}.webp`,
  );

  const originalLog = console.log;
  console.log = () => {};
  try {
    await deleteR2Objects(urls, config);
  } finally {
    console.log = originalLog;
  }

  assertEquals(maxInFlight, 16);
  assertEquals(deletedUrls.length, urls.length);
  assertEquals(
    deletedUrls[0],
    "https://account.r2.cloudflarestorage.com/media-bucket/public_uploads/free/0.webp",
  );
});

Deno.test("deleteScanMediaR2Objects skips durable avatar objects", async () => {
  const deletedUrls: string[] = [];

  const config = {
    bucketName: "media-bucket",
    endpoint: "https://account.r2.cloudflarestorage.com",
    s3Client: {
      fetch(request: Request | string) {
        const url = request instanceof Request ? request.url : request;
        deletedUrls.push(url);
        assertEquals(
          request instanceof Request ? request.method : "DELETE",
          "DELETE",
        );
        return Promise.resolve(new Response(null, { status: 204 }));
      },
    },
  } as unknown as R2Config;

  const originalWarn = console.warn;
  console.warn = () => {};
  try {
    await deleteScanMediaR2Objects([
      "https://media.merian.app/public_uploads/free/user/photo.webp",
      "https://media.merian.app/avatars/user/avatar.webp",
      "https://media.merian.app/staging/user/temp.webp",
    ], config);
  } finally {
    console.warn = originalWarn;
  }

  assertEquals(deletedUrls, [
    "https://account.r2.cloudflarestorage.com/media-bucket/public_uploads/free/user/photo.webp",
  ]);
});

Deno.test("R2 prefix helpers classify scan media separately from avatars", () => {
  assertEquals(
    isScanMediaR2Url("https://media.merian.app/public_uploads/pro/u/one.webp"),
    true,
  );
  assertEquals(
    isScanMediaR2Url("https://media.merian.app/avatars/u/avatar.webp"),
    false,
  );
  assertEquals(
    avatarR2KeyFromPublicUrl(
      "https://media.merian.app/avatars/user-1/avatar.webp",
      "user-1",
    ),
    "avatars/user-1/avatar.webp",
  );
  assertEquals(
    avatarR2KeyFromPublicUrl(
      "https://media.merian.app/avatars/user-2/avatar.webp",
      "user-1",
    ),
    null,
  );
});

Deno.test("R2 lifecycle contract does not expire durable avatar objects", () => {
  const rules = (r2Lifecycle as {
    Rules: Array<{ Status: string; Filter?: { Prefix?: string } }>;
  }).Rules;
  const expiringPrefixes = rules
    .filter((rule) => rule.Status === "Enabled")
    .map((rule) => rule.Filter?.Prefix)
    .filter(Boolean);

  assertEquals(expiringPrefixes.includes(R2_MEDIA_PREFIXES.avatars), false);
});
